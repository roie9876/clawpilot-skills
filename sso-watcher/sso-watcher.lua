-- sso-watcher.lua — Hammerspoon module for auto-selecting SSO account picker
--
-- Watches for the Microsoft SSO/Entra ID account picker modal inside a
-- target Electron app (e.g. Clawpilot) and automatically selects the
-- configured account + clicks Continue.
--
-- Usage (in ~/.hammerspoon/init.lua):
--   require("sso-watcher")
--
-- Configuration (in ~/.hammerspoon/sso-watcher-config.lua):
--   return {
--       account  = "user@microsoft.com",
--       app_name = "Clawpilot",
--       poll_interval = 3,
--       log_file = os.getenv("HOME") .. "/Scripts/sso-watcher-hammerspoon.log",
--   }

local M = {}

-- Load config with sane defaults
local function loadConfig()
    local configPath = os.getenv("HOME") .. "/.hammerspoon/sso-watcher-config.lua"
    local ok, cfg = pcall(dofile, configPath)
    if not ok or type(cfg) ~= "table" then
        hs.alert.show("⚠️ SSO Watcher: missing config!\nCreate ~/.hammerspoon/sso-watcher-config.lua", 5)
        return nil
    end
    if not cfg.account or cfg.account == "" then
        hs.alert.show("⚠️ SSO Watcher: 'account' not set in config!", 5)
        return nil
    end
    cfg.app_name      = cfg.app_name or "Clawpilot"
    cfg.poll_interval = cfg.poll_interval or 3
    cfg.log_file      = cfg.log_file or (os.getenv("HOME") .. "/Scripts/sso-watcher-hammerspoon.log")
    cfg.cooldown      = cfg.cooldown or 15
    return cfg
end

local CFG = loadConfig()
if not CFG then return M end

-- Logging
local function ensureLogDir()
    local dir = CFG.log_file:match("(.+)/[^/]+$")
    if dir then os.execute('mkdir -p "' .. dir .. '"') end
end
ensureLogDir()

local function log(msg)
    local f = io.open(CFG.log_file, "a")
    if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. msg .. "\n")
        f:close()
    end
end

-- Recursively search an AX element tree for a UI element whose
-- AXValue, AXTitle, or AXDescription contains the target string.
local function findElementWithText(element, text, maxDepth)
    maxDepth = maxDepth or 8
    if maxDepth <= 0 or not element then return nil end

    local val   = element:attributeValue("AXValue") or ""
    local title = element:attributeValue("AXTitle") or ""
    local desc  = element:attributeValue("AXDescription") or ""

    if string.find(val, text, 1, true)
       or string.find(title, text, 1, true)
       or string.find(desc, text, 1, true) then
        return element
    end

    local children = element:attributeValue("AXChildren")
    if children then
        for _, child in ipairs(children) do
            local found = findElementWithText(child, text, maxDepth - 1)
            if found then return found end
        end
    end
    return nil
end

-- Find a button/link whose title/description/value contains the given text
local function findButton(element, text, maxDepth)
    maxDepth = maxDepth or 8
    if maxDepth <= 0 or not element then return nil end

    local role  = element:attributeValue("AXRole") or ""
    local title = element:attributeValue("AXTitle") or ""
    local desc  = element:attributeValue("AXDescription") or ""
    local val   = element:attributeValue("AXValue") or ""

    if (role == "AXButton" or role == "AXLink") and
       (string.find(title, text, 1, true)
        or string.find(desc, text, 1, true)
        or string.find(val, text, 1, true)) then
        return element
    end

    local children = element:attributeValue("AXChildren")
    if children then
        for _, child in ipairs(children) do
            local found = findButton(child, text, maxDepth - 1)
            if found then return found end
        end
    end
    return nil
end

-- Check if the SSO dialog markers are present (to distinguish from
-- email content that might contain the same email address)
local function hasSSOMarkers(appElement)
    local markers = {
        "Pick an account",
        "Sign in to your account",
        "Accounts found",
        "single sign-on",
    }
    for _, marker in ipairs(markers) do
        if findElementWithText(appElement, marker) then
            return true
        end
    end
    return false
end

-- Click at the center of an element's frame, falling back to AXPress
local function clickElement(element)
    local frame = element:attributeValue("AXFrame")
    if not frame then
        local actions = element:actionNames()
        if actions then
            for _, action in ipairs(actions) do
                if action == "AXPress" then
                    element:performAction("AXPress")
                    return true
                end
            end
        end
        return false
    end
    local x = frame.x + frame.w / 2
    local y = frame.y + frame.h / 2
    hs.eventtap.leftClick(hs.geometry.point(x, y))
    return true
end

-- Cooldown tracker
local cooldownUntil = 0

-- Main check function
local function checkForSSO()
    if os.time() < cooldownUntil then return end

    local app = hs.application.find(CFG.app_name)
    if not app then return end

    local appElement = hs.axuielement.applicationElement(app)
    if not appElement then return end

    if not hasSSOMarkers(appElement) then return end

    log("SSO dialog detected — searching for account...")

    local accountEl = findElementWithText(appElement, CFG.account)
    if not accountEl then
        log("SSO markers found but account element not found yet")
        return
    end

    log("Found account element, clicking...")
    if clickElement(accountEl) then
        log("Clicked account: " .. CFG.account)
    else
        log("WARN: Could not click account element")
        return
    end

    -- Wait briefly for the Continue button to appear
    hs.timer.doAfter(0.8, function()
        local app2 = hs.application.find(CFG.app_name)
        if not app2 then return end
        local appEl2 = hs.axuielement.applicationElement(app2)
        if not appEl2 then return end

        local btnTexts = {"Continue", "Next", "Sign in", "Yes"}
        for _, btnText in ipairs(btnTexts) do
            local btn = findButton(appEl2, btnText)
            if btn then
                log("Found '" .. btnText .. "' button, clicking...")
                if clickElement(btn) then
                    log("SUCCESS: Clicked '" .. btnText .. "' — SSO complete")
                    cooldownUntil = os.time() + CFG.cooldown
                    return
                end
            end
        end
        log("WARN: Account clicked but no Continue/Next button found")
    end)
end

-- Polling timer
M._timer = hs.timer.doEvery(CFG.poll_interval, checkForSSO)
M._timer:start()

-- App activation watcher — instant trigger when the target app gets focus
M._watcher = hs.application.watcher.new(function(appName, eventType, _app)
    if appName == CFG.app_name and
       (eventType == hs.application.watcher.activated or
        eventType == hs.application.watcher.unhidden) then
        hs.timer.doAfter(0.5, checkForSSO)
    end
end)
M._watcher:start()

log("SSO auto-picker started for " .. CFG.account
    .. " in " .. CFG.app_name
    .. " (polling every " .. CFG.poll_interval .. "s + app watcher)")
hs.alert.show("SSO Auto-Picker Active ✅", 2)

return M
