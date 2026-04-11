import type { IAnalysisService } from '../../application/ports/IAnalysisService';
import type { PromptText } from '../../domain/value-objects/PromptText';

export class ElectronAnalysisService implements IAnalysisService {
  async analyze(prompt: PromptText, onChunk: (partial: string) => void): Promise<string> {
    window.electronAPI.offAiflowProgress();
    window.electronAPI.onAiflowProgress((partial) => {
      onChunk(partial);
    });

    const result = await window.electronAPI.aiflowAnalyze({ prompt: prompt.value });

    window.electronAPI.offAiflowProgress();

    if (!result.success && result.error === 'cancelled') {
      return result.response ?? '';
    }
    if (!result.success) {
      throw new Error(result.error ?? 'Analysis failed');
    }
    return result.response ?? '';
  }

  cancel(): void {
    window.electronAPI.offAiflowProgress();
    window.electronAPI.aiflowAnalyzeCancel().catch(() => {});
  }
}
