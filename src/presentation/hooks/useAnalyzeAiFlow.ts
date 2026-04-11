import { useCallback } from 'react';
import { useDI } from '../di/container';
import { useAiflowStore } from '../store/aiflowStore';
import { useCaptureStore } from '../store/captureStore';
import { useUiStore } from '../store/uiStore';

export function useAnalyzeAiFlow() {
  const { analyzeAiFlow, cancelAnalysis } = useDI();
  const setAiflowState = useAiflowStore((s) => s.setAiflowState);
  const setAiflowPartial = useAiflowStore((s) => s.setAiflowPartial);
  const setAiflowResult = useAiflowStore((s) => s.setAiflowResult);
  const captures = useCaptureStore((s) => s.captures);
  const locale = useUiStore((s) => s.locale);

  const analyze = useCallback(async () => {
    if (captures.length === 0) return;
    setAiflowState('analyzing');
    setAiflowPartial(null);
    setAiflowResult(null);
    try {
      const result = await analyzeAiFlow.execute(locale, (partial) => {
        setAiflowPartial(partial);
      });
      setAiflowState('done');
      setAiflowPartial(null);
      setAiflowResult(result);
    } catch {
      setAiflowState('error');
      setAiflowPartial(null);
    }
  }, [analyzeAiFlow, captures.length, locale, setAiflowPartial, setAiflowResult, setAiflowState]);

  const cancel = useCallback(() => {
    cancelAnalysis.execute();
    setAiflowState('idle');
    setAiflowPartial(null);
  }, [cancelAnalysis, setAiflowPartial, setAiflowState]);

  return { analyze, cancel };
}
