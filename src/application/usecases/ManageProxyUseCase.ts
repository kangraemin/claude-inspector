import type { IProxyGateway, ProxyStatus } from '../ports/IProxyGateway';
import type { ICaptureRepository } from '../../domain/repositories/ICaptureRepository';

export class ManageProxyUseCase {
  constructor(
    private readonly proxyGateway: IProxyGateway,
    private readonly captureRepo: ICaptureRepository,
  ) {}

  async start(port?: number): Promise<ProxyStatus> {
    return this.proxyGateway.start(port);
  }

  async stop(): Promise<void> {
    return this.proxyGateway.stop();
  }

  async getStatus(): Promise<ProxyStatus> {
    return this.proxyGateway.status();
  }

  clearCaptures(): void {
    this.captureRepo.clear();
  }
}
