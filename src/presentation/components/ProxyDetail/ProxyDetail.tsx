import { useCaptureStore } from '../../store/captureStore';
import { useUiStore } from '../../store/uiStore';
import { RequestTab } from './RequestTab';
import { ResponseTab } from './ResponseTab';
import { AnalysisTab } from './AnalysisTab';
import { AiFlowPanel } from '../AiFlow/AiFlowPanel';
import { ResponseParserService } from '../../../domain/services/ResponseParserService';
import type { ProxyCapture } from '../../../domain/entities/ProxyCapture';

const parser = new ResponseParserService();

type DetailTab = 'aiflow' | 'request' | 'response' | 'analysis';

const TABS: { key: DetailTab; label: string; color?: string }[] = [
  { key: 'aiflow',   label: 'AI Flow',  color: 'var(--green)' },
  { key: 'request',  label: 'Request' },
  { key: 'response', label: 'Response' },
  { key: 'analysis', label: 'Analysis', color: 'var(--purple)' },
];

function MechChipsRow({ capture }: { capture: ProxyCapture }) {
  const mechFilter = useUiStore(s => s.mechFilter);
  const setMechFilter = useUiStore(s => s.setMechFilter);
  const det = parser.detectMechanisms(capture.body);

  const chips: { key: string; cls: string; label: string }[] = [];
  if (det.claudeMd) chips.push({ key: 'cm', cls: 'cm', label: 'CLAUDE.md' });
  if (det.outputStyle) chips.push({ key: 'st', cls: 'st', label: 'Output Style' });
  if (det.slashCommand) chips.push({ key: 'sc', cls: 'sc', label: '/' + det.slashCommand.tag.slice(0, 10) });
  det.skills.forEach((_, i) => chips.push({ key: `sk_${i}`, cls: 'sk', label: 'Skill' }));
  det.subAgents.forEach((sa, i) => chips.push({ key: `sa_${i}`, cls: 'sa', label: sa.name }));

  if (chips.length === 0) return null;
  return (
    <div className="mech-chips-row">
      {chips.map(c => (
        <span
          key={c.key}
          className={`mech-chip ${c.cls}${mechFilter === c.key ? ' active' : ''}`}
          onClick={() => setMechFilter(mechFilter === c.key ? null : c.key)}
        >{c.label}</span>
      ))}
    </div>
  );
}

function SearchBar() {
  const search = useUiStore(s => s.search);
  const setSearch = useUiStore(s => s.setSearch);
  return (
    <div className="search-bar-row">
      <span style={{ fontSize: 10, color: 'var(--dim)' }}>🔍</span>
      <input
        className="search-bar-input"
        type="text"
        placeholder="Search..."
        value={search}
        onChange={e => setSearch(e.target.value)}
      />
      {search && (
        <button className="copy-small" style={{ padding: '2px 6px' }} onClick={() => setSearch('')}>✕</button>
      )}
    </div>
  );
}

export function ProxyDetail() {
  const selectedId = useCaptureStore((s) => s.selectedId);
  const captures = useCaptureStore((s) => s.captures);
  const detailTab = useUiStore((s) => s.detailTab) as DetailTab;
  const setDetailTab = useUiStore((s) => s.setDetailTab);

  const capture = captures.find((c) => c.id === selectedId);

  const copyDetail = () => {
    if (!capture) return;
    const data = detailTab === 'response' ? capture.response?.body : capture.body;
    navigator.clipboard.writeText(JSON.stringify(data, null, 2));
  };

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
        <button className="copy-small" style={{ marginLeft: 'auto' }} onClick={copyDetail}>
          Copy
        </button>
      </div>
      {capture && detailTab !== 'aiflow' && <MechChipsRow capture={capture} />}
      {capture && (detailTab === 'request' || detailTab === 'response') && <SearchBar />}
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
