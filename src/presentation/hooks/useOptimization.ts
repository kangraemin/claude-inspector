import { useCallback } from 'react';
import { useDI } from '../di/container';
import { useAiflowStore } from '../store/aiflowStore';
import { useUiStore } from '../store/uiStore';

export function useOptimization() {
  const { optimizeSession, cancelAnalysis } = useDI();
  const setOptimizing = useAiflowStore((s) => s.setOptimizing);
  const setOptPartial = useAiflowStore((s) => s.setOptPartial);
  const setOptimization = useAiflowStore((s) => s.setOptimization);
  const locale = useUiStore((s) => s.locale);

  const start = useCallback(async () => {
    setOptimizing(true);
    setOptPartial(null);
    try {
      const text = await optimizeSession.execute(locale, (partial) => {
        setOptPartial(partial);
      });
      setOptimization(text || null);
    } catch {
      // cancelled or error — leave existing optimization result
    } finally {
      setOptimizing(false);
      setOptPartial(null);
    }
  }, [locale, optimizeSession, setOptPartial, setOptimization, setOptimizing]);

  const cancel = useCallback(() => {
    cancelAnalysis.execute();
    setOptimizing(false);
    setOptPartial(null);
  }, [cancelAnalysis, setOptPartial, setOptimizing]);

  return { start, cancel };
}
