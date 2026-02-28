const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  sendToClaude: (payload, apiKey) =>
    ipcRenderer.invoke('send-to-claude', { payload, apiKey }),
  openFile: () => ipcRenderer.invoke('open-file'),
  estimateTokens: (text) => ipcRenderer.invoke('get-token-estimate', text),
  platform: process.platform,
  proxyStart: (port) => ipcRenderer.invoke('proxy-start', port),
  proxyStop: () => ipcRenderer.invoke('proxy-stop'),
  onProxyRequest: (cb) => ipcRenderer.on('proxy-request', (_, data) => cb(data)),
  onProxyResponse: (cb) => ipcRenderer.on('proxy-response', (_, data) => cb(data)),
  offProxy: () => {
    ipcRenderer.removeAllListeners('proxy-request');
    ipcRenderer.removeAllListeners('proxy-response');
  },
});
