import type { IAnalysisService } from '../ports/IAnalysisService';
import type { ICaptureRepository } from '../../domain/repositories/ICaptureRepository';
import type { AiFlowResult } from '../../domain/entities/AiFlowResult';
import { PromptText } from '../../domain/value-objects/PromptText';

export interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
}

export class SendChatMessageUseCase {
  constructor(
    private readonly analysisService: IAnalysisService,
    private readonly captureRepo: ICaptureRepository,
  ) {}

  async execute(
    messages: ChatMessage[],
    aiflowResult: AiFlowResult | null,
    onChunk: (chunk: string) => void,
  ): Promise<string> {
    const captures = this.captureRepo.getAll();
    const systemContext = this._buildSystemContext(captures, aiflowResult);
    const history = messages.slice(0, -1)
      .map(m => `${m.role === 'user' ? 'Human' : 'Assistant'}: ${m.content}`)
      .join('\n\n');
    const lastMsg = messages[messages.length - 1].content;
    const promptStr = history
      ? `${systemContext}\n\n---\n\n${history}\n\nHuman: ${lastMsg}`
      : `${systemContext}\n\n---\n\n${lastMsg}`;
    const prompt = PromptText.create(promptStr);
    return this.analysisService.analyze(prompt, onChunk);
  }

  private _buildSystemContext(captures: ReturnType<ICaptureRepository['getAll']>, aiflowResult: AiFlowResult | null): string {
    const summaryParts: string[] = ['You are a helpful assistant analyzing a Claude Code CLI session.'];
    if (aiflowResult) {
      summaryParts.push('\nAI Flow analysis result:');
      for (const step of aiflowResult.steps) {
        summaryParts.push(`STEP ${step.num}: ${step.title}\n${step.body}`);
      }
      if (aiflowResult.summary) summaryParts.push(`Summary: ${aiflowResult.summary}`);
    }
    if (captures.length > 0) {
      summaryParts.push(`\nRaw capture data for detailed questions:\n${JSON.stringify(captures.map(c => ({ id: c.id, body: c.body, response: c.response })), null, 1)}`);
    }
    return summaryParts.join('\n');
  }
}
