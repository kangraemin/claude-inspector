import { useCaptureStore } from '../../store/captureStore';
import { useUiStore } from '../../store/uiStore';
import { RequestTab } from './RequestTab';
import { ResponseTab } from './ResponseTab';
import { AnalysisTab } from './AnalysisTab';

type DetailTab = 'request' | 'response' | 'analysis';

const TABS: { key: DetailTab; label: string }[] = [
  { key: 'request', label: 'Request' },
  { key: 'response', label: 'Response' },
  { key: 'analysis', label: 'Analysis' },
];

export function ProxyDetail() {
  const selectedId = useCaptureStore((s) => s.selectedId);
  const captures = useCaptureStore((s) => s.captures);
  const detailTab = useUiStore((s) => s.detailTab) as DetailTab;
  const setDetailTab = useUiStore((s) => s.setDetailTab);

  const capture = captures.find((c) => c.id === selectedId);

  if (!capture) {
    return (
      <div className="proxy-detail">
        <div className="proxy-empty" style={{ flex: 1 }}>
          Select a request to view its payload
        </div>
      </div>
    );
  }

  return (
    <div className="proxy-detail">
      <div className="dtabs">
        {TABS.map(({ key, label }) => (
          <button
            key={key}
            className={`dtab ${detailTab === key ? 'active' : ''}`}
            onClick={() => setDetailTab(key)}
            style={key === 'analysis' ? { color: 'var(--purple)' } : undefined}
          >
            {label}
          </button>
        ))}
      </div>
      <div style={{ flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        {detailTab === 'request' && <RequestTab capture={capture} />}
        {detailTab === 'response' && <ResponseTab capture={capture} />}
        {detailTab === 'analysis' && <AnalysisTab capture={capture} />}
      </div>
    </div>
  );
}
