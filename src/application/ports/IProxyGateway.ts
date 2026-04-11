export interface ProxyStatus {
  running: boolean;
  port?: number;
  error?: string;
}

export interface IProxyGateway {
  start(port?: number): Promise<ProxyStatus>;
  stop(): Promise<void>;
  status(): Promise<ProxyStatus>;
}
