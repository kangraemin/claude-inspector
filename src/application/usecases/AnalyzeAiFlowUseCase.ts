import type { IAnalysisService } from '../ports/IAnalysisService';
import type { ICaptureRepository } from '../../domain/repositories/ICaptureRepository';
import type { PromptBuilderService } from '../../domain/services/PromptBuilderService';
import type { ResponseParserService } from '../../domain/services/ResponseParserService';
import type { AiFlowResult } from '../../domain/entities/AiFlowResult';

export class AnalyzeAiFlowUseCase {
  constructor(
    private readonly analysisService: IAnalysisService,
    private readonly captureRepo: ICaptureRepository,
    private readonly promptBuilder: PromptBuilderService,
    private readonly responseParser: ResponseParserService,
  ) {}

  async execute(locale: string, onChunk: (partial: string) => void): Promise<AiFlowResult> {
    const captures = this.captureRepo.getAll();
    const prompt = this.promptBuilder.buildAiFlowPrompt(captures, locale);
    const raw = await this.analysisService.analyze(prompt, onChunk);
    return this.responseParser.parseAiFlowResponse(raw);
  }
}
