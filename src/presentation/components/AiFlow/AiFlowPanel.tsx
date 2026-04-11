import { useAnalyzeAiFlow } from '../../hooks/useAnalyzeAiFlow';
import { useAiflowStore } from '../../store/aiflowStore';
import { useCaptureStore } from '../../store/captureStore';
import { useUiStore } from '../../store/uiStore';
import { t } from '../../../i18n';
import { Optimization } from './Optimization';
import { Chat } from './Chat';
import type { AiFlowStep } from '../../../domain/entities/AiFlowStep';

function StepCard({ step }: { step: AiFlowStep }) {
  return (
    <div className="aiflow-step">
      <div className="aiflow-step-header">
        <div className="aiflow-step-num">{step.num}</div>
        <span className="aiflow-step-title">{step.title}</span>
      </div>
      <div className="aiflow-step-body">{step.body}</div>
    </div>
  );
}

export function AiFlowPanel() {
  const { analyze, cancel } = useAnalyzeAiFlow();
  const aiflowState = useAiflowStore((s) => s.aiflowState);
  const aiflowPartial = useAiflowStore((s) => s.aiflowPartial);
  const aiflowResult = useAiflowStore((s) => s.aiflowResult);
  const captures = useCaptureStore((s) => s.captures);
  const locale = useUiStore((s) => s.locale);

  const hasCaptures = captures.length > 0;

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
        {/* Steps */}
        {aiflowResult.steps.map((step) => (
          <StepCard key={step.num} step={step} />
        ))}

        {/* Summary */}
        {aiflowResult.summary && (
          <div style={{
            fontSize: 12, lineHeight: 1.7, color: 'var(--text)',
            padding: 12, background: 'var(--surface2)',
            border: '1px solid var(--border)', borderRadius: 6,
          }}>
            <div style={{ fontSize: 10, fontWeight: 700, color: 'var(--dim)', textTransform: 'uppercase', marginBottom: 6 }}>
              {t(locale, 'aiflow.summaryTitle')}
            </div>
            <pre style={{ whiteSpace: 'pre-wrap', wordBreak: 'break-word', fontFamily: 'inherit' }}>
              {aiflowResult.summary}
            </pre>
          </div>
        )}

        {/* Re-analyze */}
        <button className="copy-small" onClick={analyze} style={{ alignSelf: 'flex-start' }}>
          {t(locale, 'aiflow.reanalyze')}
        </button>

        {/* Optimization */}
        <div style={{ borderTop: '1px solid var(--border)', paddingTop: 12 }}>
          <div style={{ fontSize: 10, fontWeight: 700, color: 'var(--dim)', textTransform: 'uppercase', marginBottom: 8 }}>
            {t(locale, 'aiflow.optimizationTitle')}
          </div>
          <Optimization />
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
          {t(locale, 'aiflow.captureCount', { count: captures.length })}
        </div>
        <button className="btn btn-send aiflow-btn-primary" onClick={analyze}>
          {t(locale, 'aiflow.analyzeBtn')}
        </button>
      </div>
    </div>
  );
}
