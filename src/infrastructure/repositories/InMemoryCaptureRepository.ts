import type { ICaptureRepository } from '../../domain/repositories/ICaptureRepository';
import { ProxyCapture, type ProxyCaptureResponse } from '../../domain/entities/ProxyCapture';

export class InMemoryCaptureRepository implements ICaptureRepository {
  private captures: ProxyCapture[] = [];

  getAll(): ProxyCapture[] {
    return [...this.captures];
  }

  add(capture: ProxyCapture): void {
    this.captures.push(capture);
  }

  updateResponse(id: number, response: ProxyCaptureResponse): void {
    const capture = this.captures.find((c) => c.id === id);
    if (capture) {
      capture.response = response;
    }
  }

  clear(): void {
    this.captures = [];
  }
}
