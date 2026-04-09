require('dotenv').config();
const fs = require('fs');
const os = require('os');
const path = require('path');

// Minimal settings file for claude -p (no hooks, keeps OAuth auth)
const claudeNoHooksSettings = path.join(os.tmpdir(), 'claude-inspector-nohooks.json');
fs.writeFileSync(claudeNoHooksSettings, JSON.stringify({ hooks: {} }));

const Sentry = require('@sentry/electron/main');
Sentry.init({
  dsn: process.env.SENTRY_DSN || process.env.SENTRY_CLIENT_KEY || '',
  environment: process.env.NODE_ENV || 'development',
  release: `claude-inspector@${require('./package.json').version}`,
  beforeSend(event) {
    if (event.breadcrumbs) {
      event.breadcrumbs = event.breadcrumbs.map(bc => {
        if (bc.data) {
          delete bc.data['x-api-key'];
          delete bc.data['X-Api-Key'];
          delete bc.data['authorization'];
          delete bc.data['Authorization'];
        }
        return bc;
      });
    }
    return event;
  },
});

const analytics = require('./analytics');

const { app, BrowserWindow, ipcMain, shell } = require('electron');
const path = require('path');
const http = require('node:http');
const https = require('node:https');

let mainWin = null;
let proxyServer = null;

// Parse SSE stream into a reconstructed Anthropic message object
function parseSseStream(text) {
  try {
    let msg = null;
    function processEvent(data) {
      try {
        const d = JSON.parse(data);
        if (d.type === 'message_start') msg = Object.assign({}, d.message, { _streaming: true });
        if (d.type === 'content_block_start' && msg) { msg.content = msg.content || []; msg.content[d.index] = Object.assign({}, d.content_block); }
        if (d.type === 'content_block_delta' && msg) { const block = msg.content && msg.content[d.index]; if (block) { if (d.delta.type === 'text_delta') block.text = (block.text || '') + d.delta.text; if (d.delta.type === 'thinking_delta') block.thinking = (block.thinking || '') + d.delta.thinking; } }
        if (d.type === 'message_delta' && msg) { if (d.delta) Object.assign(msg, d.delta); if (d.usage) msg.usage = Object.assign({}, msg.usage, d.usage); }
      } catch {}
    }
    const events = {};
    for (const rawLine of text.split('\n')) {
      const line = rawLine.replace(/\r$/, '');
      const m = line.match(/^(event|data):\s?(.*)/);
      if (m) events[m[1]] = m[2].trimEnd();
      if (line === '' && events.data) {
        processEvent(events.data);
        events.event = undefined;
        events.data = undefined;
      }
    }
    if (events.data) processEvent(events.data);
    return msg || null;
  } catch { return null; }
}

function createWindow() {
  const win = new BrowserWindow({
    width: 1320,
    height: 860,
    minWidth: 980,
    minHeight: 620,
    icon: path.join(__dirname, 'assets/icon.png'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
    titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : 'default',
    ...(process.platform === 'darwin' ? { trafficLightPosition: { x: 12, y: 19 } } : {}),
    title: 'Claude Inspector',
    backgroundColor: '#1e1e1e',
    show: false,
  });

  win.loadFile(path.join(__dirname, 'public/index.html'));

  // Retry on load failure (macOS quarantine scan can lock the asar on first launch)
  win.webContents.on('did-fail-load', () => {
    setTimeout(() => {
      if (!win.isDestroyed()) win.loadFile(path.join(__dirname, 'public/index.html'));
    }, 1500);
  });

  win.once('ready-to-show', () => win.show());
  // Fallback: force show if ready-to-show never fires
  setTimeout(() => { if (!win.isDestroyed() && !win.isVisible()) win.show(); }, 3000);
  mainWin = win;

  // Open external links in browser, not Electron
  win.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });
}

app.whenReady().then(() => {
  analytics.init(app.getPath('userData'));
  analytics.trackEvent('app_open');
  if (process.platform === 'darwin') {
    app.dock.setIcon(path.join(__dirname, 'assets/icon.png'));
  }
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    } else if (mainWin && !mainWin.isDestroyed()) {
      mainWin.show();
    }
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

ipcMain.handle('proxy-start', (_event, port = 9090) => {
  if (!Number.isInteger(port) || port < 1024 || port > 65535) {
    return { error: 'Invalid port: must be 1024–65535' };
  }
  if (proxyServer) return { running: true, port: proxyServer.address().port };

  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      req.on('error', () => {
        if (!res.headersSent) res.writeHead(400);
        res.end();
      });
      const chunks = [];
      req.on('data', chunk => chunks.push(chunk));
      req.on('end', () => {
        const bodyBuf = Buffer.concat(chunks);
        let bodyObj = null;
        try { bodyObj = JSON.parse(bodyBuf.toString()); } catch (e) { console.warn('req body parse failed:', e.message); }

        const reqId = Date.now();

        // Session detection: hash first message content as session fingerprint
        let sessionId = 'session-' + reqId;
        if (bodyObj?.messages?.length > 1) {
          const firstMsg = JSON.stringify(bodyObj.messages[0]).slice(0, 500);
          let hash = 0;
          for (let i = 0; i < firstMsg.length; i++) hash = ((hash << 5) - hash + firstMsg.charCodeAt(i)) | 0;
          sessionId = 'session-' + Math.abs(hash).toString(36);
        }

        const reqData = {
          id: reqId,
          ts: new Date().toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit', second: '2-digit' }),
          method: req.method,
          path: req.url,
          body: bodyObj,
          isApiKey: !!(req.headers['x-api-key']),
          sessionId,
        };
        if (mainWin && !mainWin.isDestroyed()) mainWin.webContents.send('proxy-request', reqData);

        const headers = Object.assign({}, req.headers, { host: 'api.anthropic.com' });
        delete headers['accept-encoding']; // Prevent gzip response so we can parse it
        const options = { hostname: 'api.anthropic.com', port: 443, path: req.url, method: req.method, headers, rejectUnauthorized: false };

        const proxyReq = https.request(options, (proxyRes) => {
          res.writeHead(proxyRes.statusCode, proxyRes.headers);
          const respChunks = [];
          proxyRes.on('data', chunk => { respChunks.push(chunk); res.write(chunk); });
          proxyRes.on('error', () => { res.end(); });
          proxyRes.on('end', () => {
            res.end();
            setImmediate(() => {
              const respStr = Buffer.concat(respChunks).toString('utf8');
              let respObj = null;
              try { respObj = JSON.parse(respStr); } catch { /* SSE stream — JSON.parse expected to fail */ }
              if (!respObj) respObj = parseSseStream(respStr);
              if (mainWin && !mainWin.isDestroyed()) {
                mainWin.webContents.send('proxy-response', {
                  id: reqId, status: proxyRes.statusCode,
                  body: respObj || respStr.slice(0, 4000),
                });
              }
            });
          });
        });

        proxyReq.on('error', (err) => {
          if (!res.headersSent) res.writeHead(502, { 'content-type': 'application/json' });
          res.end(JSON.stringify({ error: err.message }));
          if (mainWin && !mainWin.isDestroyed()) {
            mainWin.webContents.send('proxy-response', { id: reqId, error: err.message });
          }
        });

        proxyReq.end(bodyBuf);
      });
    });

    server.on('listening', () => {
      proxyServer = server;
      analytics.trackEvent('proxy_started');
      resolve({ running: true, port: server.address().port });
    });
    let retried = false;
    server.on('error', (err) => {
      if (err.code === 'EADDRINUSE' && !retried) {
        retried = true;
        server.listen(0, '127.0.0.1');
      } else {
        resolve({ error: err.message });
      }
    });
    server.listen(port, '127.0.0.1');
  });
});

ipcMain.handle('proxy-status', () => {
  if (proxyServer) {
    try { return { running: true, port: proxyServer.address().port }; }
    catch { return { running: false }; }
  }
  return { running: false };
});

ipcMain.handle('proxy-stop', () => {
  if (!proxyServer) return { stopped: true };
  const srv = proxyServer;
  proxyServer = null;
  return new Promise((resolve) => {
    srv.close(() => { resolve({ stopped: true }); });
  });
});

// ─── AI Flow: claude -p ─────────────────────────────────────────────────
ipcMain.handle('aiflow-analyze', (_event, { prompt }) => {
  const { spawn } = require('child_process');
  return new Promise((resolve) => {
    const child = spawn('claude', ['-p', '--model', 'sonnet', '--settings', claudeNoHooksSettings, prompt], { timeout: 60000 });
    let stdout = '';
    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString();
      if (mainWin && !mainWin.isDestroyed()) mainWin.webContents.send('aiflow-progress', stdout);
    });
    child.stderr.on('data', () => {});
    child.on('close', (code) => {
      if (code !== 0 && !stdout) resolve({ success: false, error: `Exit code ${code}` });
      else resolve({ success: true, response: stdout });
    });
    child.on('error', (err) => resolve({ success: false, error: err.message }));
  });
});

ipcMain.handle('aiflow-chat', (_event, { systemContext, messages }) => {
  const { spawn } = require('child_process');
  // Build full prompt: context + conversation history
  const history = messages.slice(0, -1).map(m =>
    `${m.role === 'user' ? 'Human' : 'Assistant'}: ${m.content}`
  ).join('\n\n');
  const lastMsg = messages[messages.length - 1].content;
  const prompt = history
    ? `${systemContext}\n\n---\n\n${history}\n\nHuman: ${lastMsg}`
    : `${systemContext}\n\n---\n\n${lastMsg}`;

  return new Promise((resolve) => {
    const child = spawn('claude', ['-p', '--model', 'sonnet', '--settings', claudeNoHooksSettings, prompt], { timeout: 60000 });
    let stdout = '';
    child.stdout.on('data', (chunk) => {
      const text = chunk.toString();
      stdout += text;
      if (mainWin && !mainWin.isDestroyed()) mainWin.webContents.send('aiflow-chat-chunk', text);
    });
    child.stderr.on('data', () => {});
    child.on('close', (code) => {
      if (code !== 0 && !stdout) resolve({ success: false, error: `Exit code ${code}` });
      else resolve({ success: true, response: stdout });
    });
    child.on('error', (err) => resolve({ success: false, error: err.message }));
  });
});

app.on('before-quit', () => { if (proxyServer) proxyServer.close(); });
