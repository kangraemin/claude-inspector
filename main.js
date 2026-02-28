const { app, BrowserWindow, ipcMain, shell, dialog } = require('electron');
const fs = require('fs');
const path = require('path');
const http = require('node:http');
const https = require('node:https');
const Anthropic = require('@anthropic-ai/sdk').default || require('@anthropic-ai/sdk');

let mainWin = null;
let proxyServer = null;

// Parse SSE stream into a reconstructed Anthropic message object
function parseSseStream(text) {
  try {
    const events = {};
    for (const rawLine of text.split('\n')) {
      const line = rawLine.replace(/\r$/, '');
      const m = line.match(/^(event|data):\s?(.*)/);
      if (m) events[m[1]] = m[2].trimEnd();
      if (line === '' && events.data) {
        try {
          const d = JSON.parse(events.data);
          if (d.type === 'message_start') {
            var msg = Object.assign({}, d.message, { _streaming: true });
          }
          if (d.type === 'content_block_start' && msg) {
            msg.content = msg.content || [];
            msg.content[d.index] = Object.assign({}, d.content_block);
          }
          if (d.type === 'content_block_delta' && msg) {
            const block = msg.content && msg.content[d.index];
            if (block) {
              if (d.delta.type === 'text_delta') block.text = (block.text || '') + d.delta.text;
              if (d.delta.type === 'thinking_delta') block.thinking = (block.thinking || '') + d.delta.thinking;
            }
          }
          if (d.type === 'message_delta' && msg) {
            if (d.delta) Object.assign(msg, d.delta);
            if (d.usage) msg.usage = Object.assign({}, msg.usage, d.usage);
          }
        } catch {}
        events.event = undefined;
        events.data = undefined;
      }
    }
    return msg || null;
  } catch { return null; }
}

function createWindow() {
  const win = new BrowserWindow({
    width: 1320,
    height: 860,
    minWidth: 980,
    minHeight: 620,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
    titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : 'default',
    title: 'Claude Inspector',
    backgroundColor: '#1e1e1e',
    show: false,
  });

  win.loadFile(path.join(__dirname, 'public/index.html'));

  win.once('ready-to-show', () => win.show());
  mainWin = win;

  // Open external links in browser, not Electron
  win.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });
}

app.whenReady().then(() => {
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

ipcMain.handle('send-to-claude', async (_event, { payload, apiKey }) => {
  try {
    const client = new Anthropic({ apiKey });
    const response = await client.messages.create(payload);
    return { response };
  } catch (e) {
    return { error: e.message };
  }
});

ipcMain.handle('open-file', async () => {
  const { canceled, filePaths } = await dialog.showOpenDialog({
    properties: ['openFile'],
    filters: [
      { name: 'Markdown', extensions: ['md'] },
      { name: 'All Files', extensions: ['*'] }
    ],
  });
  if (canceled || !filePaths.length) return null;
  return { path: filePaths[0], content: fs.readFileSync(filePaths[0], 'utf-8') };
});

ipcMain.handle('get-token-estimate', (_event, text) => {
  // Rough approximation: ~4 chars per token
  return Math.ceil((text || '').length / 4);
});

ipcMain.handle('proxy-start', (_event, port = 9090) => {
  if (proxyServer) return { running: true, port: proxyServer.address().port };

  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      const chunks = [];
      req.on('data', chunk => chunks.push(chunk));
      req.on('end', () => {
        const bodyBuf = Buffer.concat(chunks);
        let bodyObj = null;
        try { bodyObj = JSON.parse(bodyBuf.toString()); } catch {}

        const reqId = Date.now();
        const reqData = {
          id: reqId,
          ts: new Date().toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit', second: '2-digit' }),
          method: req.method,
          path: req.url,
          body: bodyObj,
        };
        if (mainWin && !mainWin.isDestroyed()) mainWin.webContents.send('proxy-request', reqData);

        const headers = Object.assign({}, req.headers, { host: 'api.anthropic.com' });
        delete headers['accept-encoding']; // Prevent gzip response so we can parse it
        const options = { hostname: 'api.anthropic.com', port: 443, path: req.url, method: req.method, headers };

        const proxyReq = https.request(options, (proxyRes) => {
          res.writeHead(proxyRes.statusCode, proxyRes.headers);
          const respChunks = [];
          proxyRes.on('data', chunk => { respChunks.push(chunk); res.write(chunk); });
          proxyRes.on('end', () => {
            res.end();
            const respStr = Buffer.concat(respChunks).toString('utf8');
            let respObj = null;
            try { respObj = JSON.parse(respStr); } catch {}
            if (!respObj) respObj = parseSseStream(respStr);
            if (mainWin && !mainWin.isDestroyed()) {
              mainWin.webContents.send('proxy-response', {
                id: reqId, status: proxyRes.statusCode,
                body: respObj || respStr.slice(0, 4000),
              });
            }
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
      resolve({ running: true, port: server.address().port });
    });
    server.on('error', (err) => {
      if (err.code === 'EADDRINUSE') server.listen(0, '127.0.0.1');
      else resolve({ error: err.message });
    });
    server.listen(port, '127.0.0.1');
  });
});

ipcMain.handle('proxy-stop', () => {
  if (!proxyServer) return { stopped: true };
  return new Promise((resolve) => {
    proxyServer.close(() => { proxyServer = null; resolve({ stopped: true }); });
  });
});

app.on('before-quit', () => { if (proxyServer) proxyServer.close(); });
