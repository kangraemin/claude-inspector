const { app, BrowserWindow, ipcMain, shell, dialog } = require('electron');
const fs = require('fs');
const path = require('path');
const Anthropic = require('@anthropic-ai/sdk').default || require('@anthropic-ai/sdk');

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
