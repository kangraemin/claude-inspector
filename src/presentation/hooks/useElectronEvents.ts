import { useEffect } from 'react';
import { useDI } from '../di/container';
import { useCaptureStore } from '../store/captureStore';
import { useAiflowStore } from '../store/aiflowStore';
import type { ProxyCaptureResponse } from '../../domain/entities/ProxyCapture';

export function useElectronEvents() {
  const { eventBus, captureRepository } = useDI();
  const addCapture = useCaptureStore((s) => s.addCapture);
  const setCaptures = useCaptureStore((s) => s.setCaptures);
  const addCaptureToSelection = useAiflowStore((s) => s.addCaptureToSelection);

  useEffect(() => {
    eventBus.onProxyRequest((capture) => {
      captureRepository.add(capture);
      addCapture(capture);
      addCaptureToSelection(capture.id);
    });

    eventBus.onProxyResponse((id, response: ProxyCaptureResponse) => {
      captureRepository.updateResponse(id, response);
      setCaptures(captureRepository.getAll());
    });

    return () => {
      eventBus.offProxy();
    };
  }, [addCapture, addCaptureToSelection, captureRepository, eventBus, setCaptures]);
}
