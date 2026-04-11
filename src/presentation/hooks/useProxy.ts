import { useCallback } from 'react';
import { useDI } from '../di/container';
import { useCaptureStore } from '../store/captureStore';

export function useProxy() {
  const { manageProxy } = useDI();
  const setProxyRunning = useCaptureStore((s) => s.setProxyRunning);
  const clear = useCaptureStore((s) => s.clear);

  const start = useCallback(async (port?: number) => {
    const status = await manageProxy.start(port);
    setProxyRunning(status.running, status.port);
    return status;
  }, [manageProxy, setProxyRunning]);

  const stop = useCallback(async () => {
    await manageProxy.stop();
    setProxyRunning(false, undefined);
    clear();
  }, [clear, manageProxy, setProxyRunning]);

  return { start, stop };
}
