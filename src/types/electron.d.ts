export interface ElectronAPI {
  platform: string;
  proxyStart(port?: number): Promise<{ running: boolean; port?: number; error?: string }>;
  proxyStop(): Promise<{ stopped: boolean }>;
  proxyStatus(): Promise<{ running: boolean; port?: number }>;
  onProxyRequest(cb: (data: unknown) => void): void;
  onProxyResponse(cb: (data: unknown) => void): void;
  offProxy(): void;
  aiflowAnalyze(data: { prompt: string }): Promise<{ success: boolean; response?: string; error?: string }>;
  aiflowAnalyzeCancel(): Promise<{ cancelled: boolean }>;
  onAiflowProgress(cb: (partial: string) => void): void;
  offAiflowProgress(): void;
  aiflowChat(data: { systemContext: string; messages: Array<{ role: string; content: string }> }): Promise<{ success: boolean; response?: string; error?: string }>;
  onAiflowChatChunk(cb: (chunk: string) => void): void;
  offAiflowChatChunk(): void;
  exportCaptures(data: { data: string; defaultName: string }): Promise<{ canceled?: boolean; saved?: boolean; filePath?: string }>;
  exportCaptureSessions(sessions: Array<{ filename: string; data: string }>): Promise<{ canceled?: boolean; saved?: boolean; dir?: string; count?: number }>;
  onUpdateAvailable(cb: (data: { version: string }) => void): void;
  onUpdateProgress(cb: (data: { percent: number }) => void): void;
  onUpdateDownloaded(cb: (data: { version: string }) => void): void;
  installUpdate(): Promise<void>;
}

declare global {
  interface Window {
    electronAPI: ElectronAPI;
  }
}
