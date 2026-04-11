import { useEffect, useRef, useState } from 'react';
import { useAnalyzeAiFlow } from '../../hooks/useAnalyzeAiFlow';
import { useAiflowStore } from '../../store/aiflowStore';
import { useCaptureStore } from '../../store/captureStore';
import { useUiStore } from '../../store/uiStore';
import { useOptimization } from '../../hooks/useOptimization';
import { t } from '../../../i18n';
import { Optimization } from './Optimization';
import { Chat } from './Chat';
import type { AiFlowStep } from '../../../domain/entities/AiFlowStep';

function StepCard({ step, onRefClick }: { step: AiFlowStep; onRefClick: (n: number) => void }) {
  const isSub = step.body.toLowerCase().includes('sub-agent');
  return (
    <div className="aiflow-step">
      <div className="aiflow-step-header">
        <div className={`aiflow-step-num${isSub ? ' sub' : ''}`}>{step.num}</div>
        <span className="aiflow-step-title">{step.title}</span>
        <div style={{ display: 'flex', gap: 4, flexShrink: 0 }}>
          {step.refs.map((n) => (
            <span
              key={n}
              className="aiflow-ref"
              onClick={() => onRefClick(n)}
              title={`Request #${n}`}
            >
              Req #{n}
            </span>
          ))}
        </div>
      </div>
      <div className="aiflow-step-body">{step.body}</div>
    </div>
  );
}

function MermaidChart({ code }: { code: string }) {
  const ref = useRef<HTMLPreElement>(null);

  useEffect(() => {
    if (!ref.current || !code) return;
    import('mermaid').then((m) => {
      const mermaid = m.default;
      mermaid.initialize({
        startOnLoad: false,
        theme: 'dark',
        themeVariables: {
          primaryColor: '#2d2d2d',
          primaryBorderColor: '#4ec9b0',
          lineColor: '#569cd6',
          textColor: '#d4d4d4',
        },
      });
      const sanitized = code
        .split('\n')
        .map((line) =>
          line.replace(/\["([^"]+)"\]/g, (_, label) => {
            const safe = label.replace(/"/g, "'").replace(/__/g, '_').substring(0, 50);
            return `["${safe}"]`;
          })
        )
        .join('\n');
      if (ref.current) {
        ref.current.textContent = sanitized;
        mermaid.run({ querySelector: '.aiflow-mermaid-pre' }).catch(() => {
          if (ref.current) {
            ref.current.textContent = sanitized;
            ref.current.style.fontSize = '11px';
            ref.current.style.color = 'var(--dim)';
            ref.current.style.whiteSpace = 'pre-wrap';
            ref.current.style.wordBreak = 'break-all';
          }
        });
      }
    });
  }, [code]);

  return (
    <div className="aiflow-step" style={{ borderColor: 'rgba(78,201,176,.3)' }}>
      <div className="aiflow-step-header" style={{ background: 'rgba(78,201,176,.08)' }}>
        <div className="aiflow-step-num" style={{ background: 'var(--green)' }}>⤵</div>
        <div className="aiflow-step-title" style={{ color: 'var(--green)' }}>Flow Chart</div>
      </div>
      <div className="aiflow-mermaid">
        <pre ref={ref} className="mermaid aiflow-mermaid-pre" />
      </div>
    </div>
  );
}

export function AiFlowPanel() {
  const { analyze, cancel } = useAnalyzeAiFlow();
  const { start: startOptimization } = useOptimization();
  const aiflowState = useAiflowStore((s) => s.aiflowState);
  const aiflowPartial = useAiflowStore((s) => s.aiflowPartial);
  const aiflowResult = useAiflowStore((s) => s.aiflowResult);
  const optimizing = useAiflowStore((s) => s.optimizing);
  const optimization = useAiflowStore((s) => s.optimization);
  const selectedCaptureIds = useAiflowStore((s) => s.selectedCaptureIds);
  const captures = useCaptureStore((s) => s.captures);
  const selectCapture = useCaptureStore((s) => s.selectCapture);
  const locale = useUiStore((s) => s.locale);

  const aiflowError = useAiflowStore((s) => s.aiflowError);
  const setAiflowState = useAiflowStore((s) => s.setAiflowState);
  const setAiflowError = useAiflowStore((s) => s.setAiflowError);

  const [autoOpt, setAutoOpt] = useState(() => localStorage.getItem('ci-auto-optimize') !== 'false');
  const [elapsed, setElapsed] = useState(0);
  const [tipText, setTipText] = useState('');
  const tipTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    if (aiflowState !== 'analyzing') {
      if (tipTimerRef.current) { clearInterval(tipTimerRef.current); tipTimerRef.current = null; }
      return;
    }
    const builtIn: Record<string, string[]> = {
      ko: [
        'CLAUDE.md 파일이 크면 캐시를 활용하세요',
        'system-reminder는 매 요청마다 전송됩니다',
        '불필요한 rules 파일을 줄이면 토큰을 절약할 수 있습니다',
        'Sub-Agent는 독립 API 호출을 사용합니다',
      ],
      en: [
        'Use cache for large CLAUDE.md files',
        'system-reminder is sent with every request',
        'Reduce unnecessary rules files to save tokens',
        'Sub-Agent uses independent API calls',
      ],
    };
    const arr = builtIn[locale] ?? builtIn.ko;
    function shuffle<T>(a: T[]) {
      const b = [...a];
      for (let i = b.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [b[i], b[j]] = [b[j], b[i]];
      }
      return b;
    }
    let q = shuffle(arr), idx = 0;
    setTipText(q[idx]);
    tipTimerRef.current = setInterval(() => {
      idx++;
      if (idx >= q.length) { q = shuffle(arr); idx = 0; }
      setTipText(q[idx]);
    }, 10000);
    return () => { if (tipTimerRef.current) clearInterval(tipTimerRef.current); };
  }, [aiflowState, locale]);
  const elapsedRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const prevStateRef = useRef(aiflowState);

  useEffect(() => {
    if (aiflowState === 'analyzing') {
      setElapsed(0);
      elapsedRef.current = setInterval(() => setElapsed(s => s + 1), 1000);
    } else {
      if (elapsedRef.current) { clearInterval(elapsedRef.current); elapsedRef.current = null; }
    }
    return () => { if (elapsedRef.current) clearInterval(elapsedRef.current); };
  }, [aiflowState]);

  useEffect(() => {
    if (prevStateRef.current === 'analyzing' && aiflowState === 'done') {
      if (autoOpt && !optimizing && !optimization) {
        startOptimization();
      }
    }
    prevStateRef.current = aiflowState;
  }, [aiflowState, autoOpt, optimizing, optimization, startOptimization]);

  const toggleAutoOpt = () => {
    const next = !autoOpt;
    setAutoOpt(next);
    localStorage.setItem('ci-auto-optimize', next ? 'true' : 'false');
  };

  const hasCaptures = captures.length > 0;
  const selectedCount = selectedCaptureIds.size || captures.length;

  const handleRefClick = (n: number) => {
    // n is 1-based index into captures (oldest first)
    const sorted = [...captures].sort((a, b) => a.id - b.id);
    const target = sorted[n - 1];
    if (target) selectCapture(target.id);
  };

  if (!hasCaptures) {
    return (
      <div className="aiflow-container">
        <div className="aiflow-status">
          <div className="status-icon">🔍</div>
          <div className="status-text">{t(locale, 'aiflow.noCaptures')}</div>
        </div>
      </div>
    );
  }

  if (aiflowState === 'analyzing') {
    return (
      <div className="aiflow-container">
        <div className="aiflow-status">
          <div className="aiflow-spinner" />
          <div style={{ fontSize: 12, color: 'var(--dim)' }}>{t(locale, 'aiflow.analyzing')}</div>
          <div style={{ fontSize: 11, color: 'var(--dim)', fontFamily: "'SF Mono',monospace" }} id="aiflowElapsed">{elapsed}s</div>
          {tipText && (
            <div id="aiflowTip" style={{ fontSize: 11, color: 'var(--dim)', opacity: 0.65, marginTop: 8, maxWidth: 280, textAlign: 'center', transition: 'opacity 0.4s' }}>
              {tipText}
            </div>
          )}
          {aiflowPartial && (
            <pre style={{
              fontSize: 11, color: 'var(--dim)', whiteSpace: 'pre-wrap',
              wordBreak: 'break-word', maxHeight: 300, overflow: 'auto',
              width: '100%', textAlign: 'left',
            }}>
              {aiflowPartial}
            </pre>
          )}
          <button className="aiflow-btn aiflow-btn-secondary" onClick={cancel}>
            {t(locale, 'aiflow.cancelAnalysis')}
          </button>
        </div>
      </div>
    );
  }

  if (aiflowState === 'error') {
    return (
      <div className="aiflow-container">
        <div className="aiflow-status">
          <div className="status-icon">⚠️</div>
          <div className="aiflow-error">{aiflowError || t(locale, 'aiflow.analyzeFail', { error: 'unknown' })}</div>
          <button className="aiflow-btn aiflow-btn-primary" onClick={() => { setAiflowState('idle'); setAiflowError(null); }}>
            {t(locale, 'aiflow.reanalyze')}
          </button>
        </div>
      </div>
    );
  }

  if (aiflowResult) {
    return (
      <div className="aiflow-container">
        {/* Header: summary title + reanalyze */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ fontSize: 14, fontWeight: 700, color: 'var(--green)' }}>
            {t(locale, 'aiflow.summaryTitle')}
          </div>
          <button className="aiflow-btn aiflow-btn-secondary" onClick={analyze} style={{ fontSize: 11 }}>
            {t(locale, 'aiflow.reanalyze')}
          </button>
        </div>

        {/* Steps */}
        {aiflowResult.steps.map((step) => (
          <StepCard key={step.num} step={step} onRefClick={handleRefClick} />
        ))}

        {/* Summary */}
        {aiflowResult.summary && (
          <div style={{ fontSize: 12, color: 'var(--dim)', padding: '8px 0', borderTop: '1px solid var(--border)' }}>
            {aiflowResult.summary}
          </div>
        )}

        {/* Mermaid flowchart */}
        {aiflowResult.mermaid && <MermaidChart code={aiflowResult.mermaid} />}

        {/* Optimization */}
        <div className="aiflow-step" style={{ borderColor: 'rgba(86,156,214,.3)' }}>
          <div className="aiflow-step-header" style={{ background: 'rgba(86,156,214,.08)' }}>
            <div className="aiflow-step-num" style={{ background: 'var(--blue)' }}>⚡</div>
            <div className="aiflow-step-title" style={{ color: 'var(--blue)' }}>
              {t(locale, 'aiflow.optimizationTitle')}
            </div>
            <button
              className="copy-small"
              style={{ marginLeft: 'auto', opacity: autoOpt ? 1 : 0.4 }}
              onClick={toggleAutoOpt}
              title={autoOpt ? 'Auto ON' : 'Auto OFF'}
            >Auto</button>
          </div>
          <div style={{ padding: 12 }}>
            <Optimization />
          </div>
        </div>

        {/* Chat */}
        <Chat />
      </div>
    );
  }

  return (
    <div className="aiflow-container">
      <div className="aiflow-status">
        <div className="status-icon">✨</div>
        <div className="status-text">{t(locale, 'aiflow.aiflowDesc')}</div>
        <div style={{ fontSize: 11, color: 'var(--dim)' }}>
          {t(locale, 'aiflow.captureCount', { count: selectedCount })}
        </div>
        <button className="aiflow-btn aiflow-btn-primary" onClick={analyze}>
          {t(locale, 'aiflow.analyzeBtn')}
        </button>
      </div>
    </div>
  );
}
