import type { IAnalysisService } from '../ports/IAnalysisService';
import type { ICaptureRepository } from '../../domain/repositories/ICaptureRepository';
import type { PromptBuilderService } from '../../domain/services/PromptBuilderService';

export class OptimizeSessionUseCase {
  constructor(
    private readonly analysisService: IAnalysisService,
    private readonly captureRepo: ICaptureRepository,
    private readonly promptBuilder: PromptBuilderService,
  ) {}

  async execute(locale: string, onChunk: (partial: string) => void): Promise<string> {
    const captures = this.captureRepo.getAll();
    const prompt = this.promptBuilder.buildOptimizationPrompt(captures, locale);
    return this.analysisService.analyze(prompt, onChunk);
  }
}
