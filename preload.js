const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  sendToClaude: (payload, apiKey) =>
    ipcRenderer.invoke('send-to-claude', { payload, apiKey }),
  openFile: () => ipcRenderer.invoke('open-file'),
  estimateTokens: (text) => ipcRenderer.invoke('get-token-estimate', text),
  platform: process.platform,
});
