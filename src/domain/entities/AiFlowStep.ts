/** AiFlowStep — AI Flow 분석의 개별 Step */
export interface AiFlowStep {
  num: number;
  title: string;
  body: string;
  refs: number[];        // 참조하는 Request 번호들
  highlight: string | null;
}
