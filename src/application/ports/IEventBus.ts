import type { ProxyCapture, ProxyCaptureResponse } from '../../domain/entities/ProxyCapture';

export interface IEventBus {
  onProxyRequest(handler: (capture: ProxyCapture) => void): void;
  onProxyResponse(handler: (id: number, response: ProxyCaptureResponse) => void): void;
  onAiflowProgress(handler: (partial: string) => void): void;
  offAiflowProgress(): void;
  onAiflowChatChunk(handler: (chunk: string) => void): void;
  offAiflowChatChunk(): void;
  offProxy(): void;
}
