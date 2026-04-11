import type { SessionId } from '../value-objects/SessionId';

export interface ProxyCaptureResponse {
  status: number;
  body: unknown;
}

/** ProxyCapture — 캡처된 API 요청/응답 엔티티 */
export class ProxyCapture {
  constructor(
    public readonly id: number,
    public readonly timestamp: string,
    public readonly method: string,
    public readonly path: string,
    public readonly body: Record<string, unknown> | null,
    public readonly sessionId: SessionId,
    public readonly isApiKey: boolean,
    public response?: ProxyCaptureResponse,
  ) {}

  get hasResponse(): boolean {
    return !!this.response;
  }

  withResponse(response: ProxyCaptureResponse): ProxyCapture {
    const updated = new ProxyCapture(
      this.id, this.timestamp, this.method, this.path,
      this.body, this.sessionId, this.isApiKey, response,
    );
    return updated;
  }
}
