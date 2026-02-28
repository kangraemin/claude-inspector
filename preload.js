const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  sendToClaude: (payload, apiKey) =>
    ipcRenderer.invoke('send-to-claude', { payload, apiKey }),
  platform: process.platform,
});
