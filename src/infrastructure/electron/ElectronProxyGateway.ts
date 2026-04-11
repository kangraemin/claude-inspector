import type { IProxyGateway, ProxyStatus } from '../../application/ports/IProxyGateway';

export class ElectronProxyGateway implements IProxyGateway {
  async start(port?: number): Promise<ProxyStatus> {
    const result = await window.electronAPI.proxyStart(port);
    return { running: result.running, port: result.port, error: result.error };
  }

  async stop(): Promise<void> {
    await window.electronAPI.proxyStop();
  }

  async status(): Promise<ProxyStatus> {
    const result = await window.electronAPI.proxyStatus();
    return { running: result.running, port: result.port };
  }
}
