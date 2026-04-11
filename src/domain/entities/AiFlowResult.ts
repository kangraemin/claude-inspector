import type { AiFlowStep } from './AiFlowStep';

/** AiFlowResult — AI Flow 전체 분석 결과 */
export interface AiFlowResult {
  steps: AiFlowStep[];
  summary: string;
  mermaid: string | null;
  raw: string;
}
