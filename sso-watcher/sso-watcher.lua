-- sso-watcher.lua — Hammerspoon module for auto-selecting SSO account picker
--
-- The Microsoft Entra ID / Company Portal SSO account picker appears as
-- a SEPARATE system app: "AppSSOAgent" (com.apple.AppSSOAgent), NOT inside
-- the requesting app (e.g. Clawpilot). This module watches AppSSOAgent's
-- AX tree for the picker dialog and auto-selects the configured account.
--
-- Usage (in ~/.hammerspoon/init.lua):
--   require("sso-watcher")
--
-- Configuration (in ~/.hammerspoon/sso-watcher-config.lua):
--   return {
--       account  = "user@microsoft.com",
--       poll_interval = 3,
--       log_file = os.getenv("HOME") .. "/Scripts/sso-watcher-hammerspoon.log",
--   }

local M = {}

local SSO_BUNDLE = "com.apple.AppSSOAgent"

-- Default trusted bundle IDs used when the config does not specify its own list.
-- These are the apps most likely to legitimately trigger an SSO prompt.
local DEFAULT_TRUSTED_BUNDLES = {
    "com.apple.AppSSOAgent",
    "com.microsoft.teams",
    "com.microsoft.edgemac",
    "com.google.Chrome",
    "org.mozilla.firefox",
    "com.apple.Safari",
}

-- Paths under which the real AppSSOAgent binary must reside (SIP-protected).
-- Not user-configurable: relaxing this would undermine spoofing protection.
local SSO_TRUSTED_PATH_PREFIXES = {
    "/System/Library/",
    "/Library/Apple/",
}

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

    cfg.poll_interval = cfg.poll_interval or 3
    cfg.log_file      = cfg.log_file or (os.getenv("HOME") .. "/Scripts/sso-watcher-hammerspoon.log")
    cfg.cooldown      = cfg.cooldown or 15

    -- notifications: enabled by default; set to false in config to suppress
    if cfg.notifications == nil then cfg.notifications = true end

    -- Build a fast lookup set from the config list (or fall back to defaults)
    local bundles = cfg.trusted_bundles or DEFAULT_TRUSTED_BUNDLES
    cfg._trusted_set = {}
    for _, bid in ipairs(bundles) do
        cfg._trusted_set[bid] = true
    end

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

-- Find the AppSSOAgent app (system SSO broker from Company Portal)
local function findSSOApp()
    local app = hs.application.find(SSO_BUNDLE)
    if not app then
        for _, a in ipairs(hs.application.runningApplications()) do
            if (a:bundleID() or "") == SSO_BUNDLE then
                app = a
                break
            end
        end
    end
    if not app then return nil end

    -- Validate the executable path to guard against bundle-ID spoofing.
    local execPath = app:path() or ""
    local trusted = false
    for _, prefix in ipairs(SSO_TRUSTED_PATH_PREFIXES) do
        if execPath:sub(1, #prefix) == prefix then
            trusted = true
            break
        end
    end
    if not trusted then
        log("SECURITY: AppSSOAgent found but path not trusted: " .. execPath)
        return nil
    end

    return app
end

-- Recursively search an AX element tree for a UI element whose
-- AXValue or AXTitle contains the target string.
local function findElementWithText(element, text, maxDepth)
    maxDepth = maxDepth or 10
    if maxDepth <= 0 or not element then return nil end

    local val = tostring(element:attributeValue("AXValue") or "")
    local title = tostring(element:attributeValue("AXTitle") or "")

    if string.find(val, text, 1, true)
       or string.find(title, text, 1, true) then
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

-- Find a button whose AXTitle contains the given text
local function findButton(element, text, maxDepth)
    maxDepth = maxDepth or 10
    if maxDepth <= 0 or not element then return nil end

    local role = tostring(element:attributeValue("AXRole") or "")
    local title = tostring(element:attributeValue("AXTitle") or "")

    if role == "AXButton" and string.find(title, text, 1, true) then
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

-- Find the AXRow containing the target account email.
-- SSO dialog structure: AXTable > AXRow > AXCell > AXStaticText
-- Click the ROW to select the account.
local function findAccountRow(element, account, maxDepth)
    maxDepth = maxDepth or 10
    if maxDepth <= 0 or not element then return nil end

    local role = tostring(element:attributeValue("AXRole") or "")

    if role == "AXRow" then
        if findElementWithText(element, account, 5) then
            return element
        end
        return nil
    end

    local children = element:attributeValue("AXChildren")
    if children then
        for _, child in ipairs(children) do
            local found = findAccountRow(child, account, maxDepth - 1)
            if found then return found end
        end
    end
    return nil
end

-- Check if the SSO dialog markers are present
local function hasSSOMarkers(appElement)
    local markers = {
        "Accounts found",
        "Pick an account",
        "Sign in to your account",
        "single sign-on",
    }
    for _, marker in ipairs(markers) do
        if findElementWithText(appElement, marker) then
            return true
        end
    end
    return false
end

-- Click an element via AXPress (preferred) or frame center click (fallback)
local function clickElement(element)
    local actions = element:actionNames()
    if actions then
        for _, action in ipairs(actions) do
            if action == "AXPress" then
                element:performAction("AXPress")
                return true
            end
        end
    end
    local frame = element:attributeValue("AXFrame")
    if frame then
        local x = frame.x + frame.w / 2
        local y = frame.y + frame.h / 2
        hs.eventtap.leftClick(hs.geometry.point(x, y))
        return true
    end
    return false
end

-- Cooldown tracker
local cooldownUntil = 0

-- Send a macOS notification (no-op when notifications are disabled in config)
local function notify(title, body)
    if not CFG.notifications then return end
    hs.notify.new({
        title           = title,
        informativeText = body,
        withdrawAfter   = 6,
    }):send()
end

-- Main check function
-- triggeringAppName: display name of the app whose activation caused this check
local function checkForSSO(triggeringAppName)
    if os.time() < cooldownUntil then return end

    local app = findSSOApp()
    if not app then return end

    local wins = app:allWindows()
    if not wins or #wins == 0 then return end

    local appElement = hs.axuielement.applicationElement(app)
    if not appElement then return end

    if not hasSSOMarkers(appElement) then return end

    log("SSO dialog detected in AppSSOAgent — searching for account...")

    local row = findAccountRow(appElement, CFG.account)
    if not row then
        log("SSO markers found but account row not found")
        return
    end

    log("Found account row, clicking...")
    if clickElement(row) then
        log("Clicked account row: " .. CFG.account)
    else
        log("WARN: Could not click account row")
        return
    end

    -- Wait for the Continue button to become active
    hs.timer.doAfter(0.8, function()
        local app2 = findSSOApp()
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
                    local appLabel = triggeringAppName or "Unknown app"
                    notify("SSO Handled", "Signed in automatically for " .. appLabel)
                    return
                end
            end
        end
        log("WARN: Account clicked but no Continue/Next button found")
    end)
end

-- Polling timer — no triggering app known, pass nil
M._timer = hs.timer.doEvery(CFG.poll_interval, function() checkForSSO(nil) end)
M._timer:start()

-- App activation watcher — only trigger for trusted apps that legitimately
-- cause SSO prompts; all other activations are ignored.
M._watcher = hs.application.watcher.new(function(appName, eventType, app)
    if eventType ~= hs.application.watcher.activated and
       eventType ~= hs.application.watcher.unhidden and
       eventType ~= hs.application.watcher.launched then
        return
    end
    local bid = (app and app:bundleID()) or ""
    if not CFG._trusted_set[bid] then return end
    local displayName = appName or bid
    hs.timer.doAfter(0.5, function() checkForSSO(displayName) end)
end)
M._watcher:start()

log("SSO auto-picker started — watching AppSSOAgent for " .. CFG.account
    .. " (polling every " .. CFG.poll_interval .. "s + app watcher)")
hs.alert.show("SSO Auto-Picker Active ✅", 2)

return M
