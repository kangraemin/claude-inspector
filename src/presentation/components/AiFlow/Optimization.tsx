import { useOptimization } from '../../hooks/useOptimization';
import { useAiflowStore } from '../../store/aiflowStore';
import { useUiStore } from '../../store/uiStore';
import { t } from '../../../i18n';
import { Spinner } from '../shared/Spinner';
import { ElapsedTimer } from '../shared/ElapsedTimer';

export function Optimization() {
  const { start, cancel } = useOptimization();
  const optimizing = useAiflowStore((s) => s.optimizing);
  const optPartial = useAiflowStore((s) => s.optPartial);
  const optimization = useAiflowStore((s) => s.optimization);
  const locale = useUiStore((s) => s.locale);

  if (optimizing) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12 }}>
          <Spinner size={14} color="var(--green)" />
          <span>{t(locale, 'aiflow.analyzing')}</span>
          <ElapsedTimer running={optimizing} />
          <button className="copy-small" onClick={cancel} style={{ marginLeft: 'auto' }}>
            {t(locale, 'aiflow.cancelAnalysis')}
          </button>
        </div>
        {optPartial && (
          <pre style={{
            fontSize: 11, color: 'var(--dim)', whiteSpace: 'pre-wrap',
            wordBreak: 'break-word', maxHeight: 200, overflow: 'auto',
            background: 'var(--surface2)', padding: 8, borderRadius: 5,
            border: '1px solid var(--border)',
          }}>
            {optPartial}
          </pre>
        )}
      </div>
    );
  }

  if (optimization) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        <pre style={{
          fontSize: 12, whiteSpace: 'pre-wrap', wordBreak: 'break-word',
          lineHeight: 1.6, color: 'var(--text)',
        }}>
          {optimization}
        </pre>
        <button className="copy-small" onClick={start} style={{ alignSelf: 'flex-start' }}>
          {t(locale, 'aiflow.reanalyze')}
        </button>
      </div>
    );
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      <p style={{ fontSize: 12, color: 'var(--dim)', lineHeight: 1.6 }}>
        {t(locale, 'aiflow.optimizationDesc')}
      </p>
      <button className="btn btn-send" onClick={start} style={{ alignSelf: 'flex-start' }}>
        ⚡ {t(locale, 'aiflow.optimizationTitle')}
      </button>
    </div>
  );
}
