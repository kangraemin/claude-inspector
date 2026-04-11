import type { IAnalysisService } from '../ports/IAnalysisService';

export class CancelAnalysisUseCase {
  constructor(private readonly analysisService: IAnalysisService) {}

  execute(): void {
    this.analysisService.cancel();
  }
}
