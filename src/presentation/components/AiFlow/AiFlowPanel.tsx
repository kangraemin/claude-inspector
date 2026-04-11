import { useEffect, useRef } from 'react';
import { useAnalyzeAiFlow } from '../../hooks/useAnalyzeAiFlow';
import { useAiflowStore } from '../../store/aiflowStore';
import { useCaptureStore } from '../../store/captureStore';
import { useUiStore } from '../../store/uiStore';
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
  const aiflowState = useAiflowStore((s) => s.aiflowState);
  const aiflowPartial = useAiflowStore((s) => s.aiflowPartial);
  const aiflowResult = useAiflowStore((s) => s.aiflowResult);
  const selectedCaptureIds = useAiflowStore((s) => s.selectedCaptureIds);
  const captures = useCaptureStore((s) => s.captures);
  const selectCapture = useCaptureStore((s) => s.selectCapture);
  const locale = useUiStore((s) => s.locale);

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
          {aiflowPartial && (
            <pre style={{
              fontSize: 11, color: 'var(--dim)', whiteSpace: 'pre-wrap',
              wordBreak: 'break-word', maxHeight: 300, overflow: 'auto',
              width: '100%', textAlign: 'left',
            }}>
              {aiflowPartial}
            </pre>
          )}
          <button className="copy-small" onClick={cancel}>
            {t(locale, 'aiflow.cancelAnalysis')}
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
          <button className="copy-small" onClick={analyze} style={{ fontSize: 11 }}>
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
        <button className="btn btn-send aiflow-btn-primary" onClick={analyze}>
          {t(locale, 'aiflow.analyzeBtn')}
        </button>
      </div>
    </div>
  );
}
