import type { IEventBus } from '../../application/ports/IEventBus';
import { ProxyCapture, type ProxyCaptureResponse } from '../../domain/entities/ProxyCapture';
import { SessionId } from '../../domain/value-objects/SessionId';

export class ElectronEventBus implements IEventBus {
  onProxyRequest(handler: (capture: ProxyCapture) => void): void {
    window.electronAPI.onProxyRequest((raw) => {
      const data = raw as {
        id: number; ts: string; method: string; path: string;
        body: Record<string, unknown> | null; sessionId: string; isApiKey: boolean;
      };
      const capture = new ProxyCapture(
        data.id, data.ts, data.method, data.path,
        data.body, SessionId.fromRaw(data.sessionId), data.isApiKey,
      );
      handler(capture);
    });
  }

  onProxyResponse(handler: (id: number, response: ProxyCaptureResponse) => void): void {
    window.electronAPI.onProxyResponse((raw) => {
      const data = raw as { id: number; status?: number; body?: unknown; error?: string };
      handler(data.id, { status: data.status ?? 0, body: data.body ?? data.error });
    });
  }

  onAiflowProgress(handler: (partial: string) => void): void {
    window.electronAPI.onAiflowProgress(handler);
  }

  offAiflowProgress(): void {
    window.electronAPI.offAiflowProgress();
  }

  onAiflowChatChunk(handler: (chunk: string) => void): void {
    window.electronAPI.onAiflowChatChunk(handler);
  }

  offAiflowChatChunk(): void {
    window.electronAPI.offAiflowChatChunk();
  }

  offProxy(): void {
    window.electronAPI.offProxy();
  }
}
