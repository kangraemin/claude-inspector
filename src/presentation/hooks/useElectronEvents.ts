import { useEffect } from 'react';
import { useDI } from '../di/container';
import { useCaptureStore } from '../store/captureStore';
import type { ProxyCaptureResponse } from '../../domain/entities/ProxyCapture';

export function useElectronEvents() {
  const { eventBus, captureRepository } = useDI();
  const addCapture = useCaptureStore((s) => s.addCapture);
  const setCaptures = useCaptureStore((s) => s.setCaptures);

  useEffect(() => {
    eventBus.onProxyRequest((capture) => {
      captureRepository.add(capture);
      addCapture(capture);
    });

    eventBus.onProxyResponse((id, response: ProxyCaptureResponse) => {
      captureRepository.updateResponse(id, response);
      // Trigger re-render by refreshing captures snapshot
      setCaptures(captureRepository.getAll());
    });

    return () => {
      eventBus.offProxy();
    };
  }, [addCapture, captureRepository, eventBus, setCaptures]);
}
