import type { PromptText } from '../../domain/value-objects/PromptText';

export interface IAnalysisService {
  /** 프롬프트를 분석하고 누적 텍스트를 스트리밍으로 yield */
  analyze(prompt: PromptText, onChunk: (partial: string) => void): Promise<string>;
  cancel(): void;
}
