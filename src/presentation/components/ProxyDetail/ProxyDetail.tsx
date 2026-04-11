import { useCaptureStore } from '../../store/captureStore';
import { useUiStore } from '../../store/uiStore';
import { RequestTab } from './RequestTab';
import { ResponseTab } from './ResponseTab';
import { AnalysisTab } from './AnalysisTab';
import { AiFlowPanel } from '../AiFlow/AiFlowPanel';

type DetailTab = 'aiflow' | 'request' | 'response' | 'analysis';

const TABS: { key: DetailTab; label: string; color?: string }[] = [
  { key: 'aiflow',   label: 'AI Flow',  color: 'var(--green)' },
  { key: 'request',  label: 'Request' },
  { key: 'response', label: 'Response' },
  { key: 'analysis', label: 'Analysis', color: 'var(--purple)' },
];

export function ProxyDetail() {
  const selectedId = useCaptureStore((s) => s.selectedId);
  const captures = useCaptureStore((s) => s.captures);
  const detailTab = useUiStore((s) => s.detailTab) as DetailTab;
  const setDetailTab = useUiStore((s) => s.setDetailTab);

  const capture = captures.find((c) => c.id === selectedId);

  return (
    <div className="proxy-detail">
      <div className="dtabs">
        {TABS.map(({ key, label, color }) => (
          <button
            key={key}
            className={`dtab ${detailTab === key ? 'active' : ''}`}
            onClick={() => setDetailTab(key)}
            style={color ? { color } : undefined}
          >
            {label}
          </button>
        ))}
      </div>
      <div style={{ flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        {detailTab === 'aiflow' && <AiFlowPanel />}
        {detailTab !== 'aiflow' && !capture && (
          <div className="proxy-empty" style={{ flex: 1 }}>
            <span style={{ fontSize: 28 }}>🔍</span>
            <span>요청을 선택하면<br />페이로드가 표시됩니다</span>
          </div>
        )}
        {detailTab === 'request'  && capture && <RequestTab capture={capture} />}
        {detailTab === 'response' && capture && <ResponseTab capture={capture} />}
        {detailTab === 'analysis' && capture && <AnalysisTab capture={capture} />}
      </div>
    </div>
  );
}
