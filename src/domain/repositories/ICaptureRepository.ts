import type { ProxyCapture, ProxyCaptureResponse } from '../entities/ProxyCapture';

export interface ICaptureRepository {
  getAll(): ProxyCapture[];
  add(capture: ProxyCapture): void;
  updateResponse(id: number, response: ProxyCaptureResponse): void;
  clear(): void;
}
