const vscode = require('vscode');
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 19876;
const NUDGE_FILE = path.join(process.env.HOME, '.copilot', 'nudge-queue.txt');
let server = null;
let outputChannel = null;

function activate(context) {
    outputChannel = vscode.window.createOutputChannel('Copilot Nudge');
    outputChannel.appendLine('[copilot-nudge] Activating v2...');
    
    server = http.createServer(async (req, res) => {
        if (req.method === 'POST' && req.url === '/nudge') {
            let body = '';
            req.on('data', chunk => body += chunk);
            req.on('end', async () => {
                try {
                    const { message, sessionId } = JSON.parse(body);
                    const result = await sendNudge(message, sessionId);
                    res.writeHead(200, {'Content-Type': 'application/json'});
                    res.end(JSON.stringify({ success: true, result }));
                } catch (e) {
                    res.writeHead(500, {'Content-Type': 'application/json'});
                    res.end(JSON.stringify({ success: false, error: e.message }));
                }
            });
        } else if (req.method === 'GET' && req.url === '/health') {
            res.writeHead(200, {'Content-Type': 'application/json'});
            res.end(JSON.stringify({ status: 'ok', port: PORT, version: 2 }));
        } else if (req.method === 'GET' && req.url === '/commands') {
            // Diagnostic: list all chat-related commands
            const allCmds = await vscode.commands.getCommands(true);
            const chatCmds = allCmds.filter(c => c.includes('chat'));
            res.writeHead(200, {'Content-Type': 'application/json'});
            res.end(JSON.stringify({ commands: chatCmds }));
        } else {
            res.writeHead(404);
            res.end('Not found');
        }
    });

    server.listen(PORT, '127.0.0.1', () => {
        outputChannel.appendLine(`[copilot-nudge] HTTP server on http://127.0.0.1:${PORT}`);
    });

    server.on('error', (e) => {
        if (e.code === 'EADDRINUSE') {
            server.listen(PORT + 1, '127.0.0.1');
        }
    });

    setupFileWatcher();

    context.subscriptions.push(
        vscode.commands.registerCommand('copilot-nudge.sendMessage', async () => {
            const message = await vscode.window.showInputBox({ prompt: 'Message to send to Copilot' });
            if (message) await sendNudge(message);
        })
    );

    context.subscriptions.push({ dispose: () => { if (server) server.close(); } });
}

async function sendNudge(message, sessionId) {
    outputChannel.appendLine(`[nudge] Sending: "${message}"`);
    
    // Strategy A: chat.open with isPartialQuery=false (auto-submits in VS Code 1.90+)
    try {
        outputChannel.appendLine('[nudge] Strategy A: chat.open with auto-submit');
        await vscode.commands.executeCommand('workbench.action.chat.open', {
            query: message,
            isPartialQuery: false
        });
        // Give VS Code time to process
        await sleep(1000);
        outputChannel.appendLine('[nudge] Strategy A executed');
        return 'sent-via-chatOpen-autoSubmit';
    } catch (e) {
        outputChannel.appendLine(`[nudge] Strategy A failed: ${e.message}`);
    }

    // Strategy B: acceptInput (the internal submit)
    try {
        outputChannel.appendLine('[nudge] Strategy B: focusInput + type + acceptInput');
        await vscode.commands.executeCommand('workbench.action.chat.open', {
            query: message,
            isPartialQuery: true
        });
        await sleep(500);
        await vscode.commands.executeCommand('workbench.action.chat.acceptInput');
        outputChannel.appendLine('[nudge] Strategy B executed');
        return 'sent-via-acceptInput';
    } catch (e) {
        outputChannel.appendLine(`[nudge] Strategy B failed: ${e.message}`);
    }

    // Strategy C: Use interactive session API if available
    try {
        outputChannel.appendLine('[nudge] Strategy C: interactiveSession.sendRequest');
        await vscode.commands.executeCommand('workbench.action.chat.sendToNewChat', {
            inputValue: message
        });
        outputChannel.appendLine('[nudge] Strategy C executed');
        return 'sent-via-sendToNewChat';
    } catch (e) {
        outputChannel.appendLine(`[nudge] Strategy C failed: ${e.message}`);
    }

    throw new Error('All strategies failed');
}

function setupFileWatcher() {
    const dir = path.dirname(NUDGE_FILE);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    
    setInterval(async () => {
        try {
            if (fs.existsSync(NUDGE_FILE)) {
                const content = fs.readFileSync(NUDGE_FILE, 'utf8').trim();
                if (content) {
                    fs.unlinkSync(NUDGE_FILE);
                    const lines = content.split('\n');
                    await sendNudge(lines[0], lines[1] || undefined);
                }
            }
        } catch (e) {
            outputChannel.appendLine(`[nudge] File watcher error: ${e.message}`);
        }
    }, 2000);
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

function deactivate() {
    if (server) server.close();
}

module.exports = { activate, deactivate };
