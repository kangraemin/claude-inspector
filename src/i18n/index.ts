const strings = {
  ko: {
    header: { logoSub: 'Prompt Mechanism Visualizer' },
    proxy: {
      title: 'Proxy Control',
      liveCapture: '실시간 캡처',
      interceptTitle: '⚡ 실제 API 트래픽 인터셉트',
      interceptDesc: 'Claude Code CLI의 실제 API 요청을 가로채 실시간으로 시각화합니다.',
      port: '포트',
      stopped: '중지됨',
      running: '포트 {port}에서 실행 중',
      runCommand: '실행 명령',
      startFirst: '프록시를 먼저 시작하세요',
      startProxy: 'Start Proxy',
      stopProxy: 'Stop Proxy',
      clear: 'Clear',
      capturedRequests: '캡처된 요청',
      noCaptures: '캡처된 요청 없음',
      selectRequest: '요청을 선택하면\n페이로드가 표시됩니다',
      waitingResponse: '응답 대기 중…',
      noBody: '바디 없음',
    },
    aiflow: {
      noCaptures: '분석할 캡처 데이터가 없습니다.',
      aiflowDesc: 'Claude(Sonnet)로 캡처된 API 요청을 분석합니다.',
      analyzeBtn: '세션 흐름 분석하기',
      analyzing: 'Claude(Sonnet)로 분석 중...',
      reanalyze: '다시 분석',
      captureCount: '선택된 {count}개의 요청을 분석합니다',
      summaryTitle: '세션 흐름 요약',
      optimizationTitle: '최적화 조언',
      cancelAnalysis: '취소',
      optimizationDesc: 'CLAUDE.md, rules 파일 크기 및 토큰 최적화 기회를 분석합니다.',
      flowChartTitle: 'Flow Chart',
      chatHeader: '💬 이 세션에 대해 Claude에게 물어보세요',
      chatPlaceholder: '이 세션에 대해 무엇이든 물어보세요…',
      chatSend: '전송',
    },
    analysis: {
      noMechanisms: '감지된 메커니즘 없음',
      claudeMdTitle: 'CLAUDE.md — system-reminder 주입',
      outputStyleTitle: 'Output Style — system[] 추가 블록',
      slashCmdTitle: '① 입력 — Slash Command',
      skillTitle: 'Skill (tool_use → tool_result)',
      subAgentTitle: 'Sub-Agent',
    },
    copy: { copy: '복사', copied: '✓ 복사됨' },
    onboard: {
      title: 'Claude Inspector 시작하기',
      sub: 'Claude Code가 API에 실제로 보내는 내용을 실시간으로 확인하세요',
      step1: '아래 <b>Start Proxy</b> 버튼 클릭 → 로컬 프록시(localhost:9090) 시작',
      step2: '새 터미널을 열고 아래 명령어로 Claude Code 실행:',
      step3: 'AI Flow · Request · Analysis 탭에서 캡처된 트래픽 확인',
      note: '💡 프록시는 로컬에서만 동작합니다.',
      btn: '시작하기 →',
    },
  },
  en: {
    header: { logoSub: 'Prompt Mechanism Visualizer' },
    proxy: {
      title: 'Proxy Control',
      liveCapture: 'Live Capture',
      interceptTitle: '⚡ Live API Traffic Intercept',
      interceptDesc: 'Intercepts real API requests from the Claude Code CLI.',
      port: 'Port',
      stopped: 'Stopped',
      running: 'Running on port {port}',
      runCommand: 'Run Command',
      startFirst: 'Start the proxy first',
      startProxy: 'Start Proxy',
      stopProxy: 'Stop Proxy',
      clear: 'Clear',
      capturedRequests: 'Captured Requests',
      noCaptures: 'No captured requests',
      selectRequest: 'Select a request to\nview its payload',
      waitingResponse: 'Waiting for response…',
      noBody: 'No body',
    },
    aiflow: {
      noCaptures: 'No capture data to analyze.',
      aiflowDesc: 'Analyzes captured API requests using Claude (Sonnet).',
      analyzeBtn: 'Analyze Session Flow',
      analyzing: 'Analyzing with Claude (Sonnet)...',
      reanalyze: 'Re-analyze',
      captureCount: 'Analyzing {count} selected requests',
      summaryTitle: 'Session Flow Summary',
      optimizationTitle: 'Optimization Advice',
      cancelAnalysis: 'Cancel',
      optimizationDesc: 'Analyze CLAUDE.md, rules file sizes, and token optimization opportunities.',
      flowChartTitle: 'Flow Chart',
      chatHeader: '💬 Ask Claude about this session',
      chatPlaceholder: 'Ask anything about this session…',
      chatSend: 'Send',
    },
    analysis: {
      noMechanisms: 'No mechanisms detected',
      claudeMdTitle: 'CLAUDE.md — system-reminder injection',
      outputStyleTitle: 'Output Style — system[] extra block',
      slashCmdTitle: '① Input — Slash Command',
      skillTitle: 'Skill (tool_use → tool_result)',
      subAgentTitle: 'Sub-Agent',
    },
    copy: { copy: 'Copy', copied: '✓ Copied' },
    onboard: {
      title: 'Getting Started',
      sub: 'See what Claude Code actually sends to the API — in real-time',
      step1: 'Click <b>Start Proxy</b> — starts a local proxy on localhost:9090',
      step2: 'Open a new terminal and run Claude Code:',
      step3: 'Browse captured traffic in AI Flow · Request · Analysis tabs',
      note: '💡 The proxy runs locally only.',
      btn: 'Get Started →',
    },
  },
} as const;

type Locale = 'ko' | 'en';

export function t(locale: Locale, key: string, vars?: Record<string, string | number>): string {
  const parts = key.split('.');
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let val: any = strings[locale];
  for (const p of parts) {
    if (val == null) return key;
    val = val[p];
  }
  if (typeof val !== 'string') return key;
  if (vars) {
    return val.replace(/\{(\w+)\}/g, (_, k) => String(vars[k] ?? ''));
  }
  return val;
}
