try { require('@sentry/electron/renderer').init(); } catch {}

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  platform: process.platform,
  proxyStart: (port) => ipcRenderer.invoke('proxy-start', port),
  proxyStop: () => ipcRenderer.invoke('proxy-stop'),
  proxyStatus: () => ipcRenderer.invoke('proxy-status'),
  onProxyRequest: (cb) => ipcRenderer.on('proxy-request', (_, data) => cb(data)),
  onProxyResponse: (cb) => ipcRenderer.on('proxy-response', (_, data) => cb(data)),
  ollamaStatus: () => ipcRenderer.invoke('ollama-status'),
  ollamaPull: (model) => ipcRenderer.invoke('ollama-pull', model),
  ollamaAnalyze: (data) => ipcRenderer.invoke('ollama-analyze', data),
  onOllamaPullProgress: (cb) => ipcRenderer.on('ollama-pull-progress', (_, data) => cb(data)),
  offOllamaPullProgress: () => ipcRenderer.removeAllListeners('ollama-pull-progress'),
  offProxy: () => {
    ipcRenderer.removeAllListeners('proxy-request');
    ipcRenderer.removeAllListeners('proxy-response');
  },
});
