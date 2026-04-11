import { useState } from 'react';
import { useCaptureStore } from '../../store/captureStore';
import { useUiStore } from '../../store/uiStore';
import { RequestTab } from './RequestTab';
import { ResponseTab } from './ResponseTab';
import { AnalysisTab } from './AnalysisTab';
import { AiFlowPanel } from '../AiFlow/AiFlowPanel';
import { ResponseParserService } from '../../../domain/services/ResponseParserService';
import { t } from '../../../i18n';
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
  const locale = useUiStore(s => s.locale);
  const det = parser.detectMechanisms(capture.body);

  const chips: { key: string; cls: string; label: string; metaKey: string }[] = [];
  if (det.claudeMd) {
    const sects = parser.parseClaudeMdSections(det.claudeMd);
    if (sects.length > 0) sects.forEach((s, i) => chips.push({ key: `cm_${i}`, cls: 'cm', label: s.label, metaKey: 'cm' }));
    else chips.push({ key: 'cm', cls: 'cm', label: 'CLAUDE.md', metaKey: 'cm' });
  }
  if (det.outputStyle) chips.push({ key: 'st', cls: 'st', label: 'Output Style', metaKey: 'st' });
  if (det.slashCommand) chips.push({ key: 'sc', cls: 'sc', label: '/' + det.slashCommand.tag.slice(0, 10), metaKey: 'sc' });
  det.skills.forEach((_, i) => chips.push({ key: `sk_${i}`, cls: 'sk', label: 'Skill', metaKey: 'sk' }));
  det.subAgents.forEach((sa, i) => chips.push({ key: `sa_${i}`, cls: 'sa', label: sa.name, metaKey: 'sa' }));
  det.mcpTools.forEach((m, i) => {
    const parts = m.name.split('__');
    const toolName = parts.slice(2).join('__') || m.name;
    chips.push({ key: `mc_${i}`, cls: 'mc', label: `🔌 ${toolName}`, metaKey: 'mc' });
  });

  if (chips.length === 0) return null;

  const META: Record<string, { color: string; who: string; what: string }> = {
    cm: { color: 'var(--green)',  who: t(locale, 'mechDesc.cm.who'), what: t(locale, 'mechDesc.cm.what') },
    st: { color: 'var(--blue)',   who: t(locale, 'mechDesc.st.who'), what: t(locale, 'mechDesc.st.what') },
    sc: { color: 'var(--yellow)', who: t(locale, 'mechDesc.sc.who'), what: t(locale, 'mechDesc.sc.what') },
    sk: { color: 'var(--purple)', who: t(locale, 'mechDesc.sk.who'), what: t(locale, 'mechDesc.sk.what') },
    sa: { color: 'var(--orange)', who: t(locale, 'mechDesc.sa.who'), what: t(locale, 'mechDesc.sa.what') },
    mc: { color: '#4fc1ff',       who: t(locale, 'mechDesc.mc.who'), what: t(locale, 'mechDesc.mc.what') },
  };
  const activeChip = chips.find(c => c.key === mechFilter);
  const meta = activeChip ? META[activeChip.metaKey] : null;

  return (
    <div style={{ flexShrink: 0, borderBottom: '1px solid var(--border)' }}>
      <div className="mech-chips-row" style={{ borderBottom: 'none' }}>
        {chips.map(c => (
          <span
            key={c.key}
            className={`mech-chip ${c.cls}${mechFilter === c.key ? ' active' : ''}`}
            onClick={() => setMechFilter(mechFilter === c.key ? null : c.key)}
          >{c.label}</span>
        ))}
      </div>
      {meta && (
        <div className="mech-filter-desc">
          <span className="mech-filter-desc-dot" style={{ background: meta.color }} />
          <div className="mech-filter-desc-body">
            <span className="mech-filter-desc-who">{meta.who}</span>
            <span className="mech-filter-desc-what">{meta.what}</span>
          </div>
        </div>
      )}
    </div>
  );
}

function SearchBar() {
  const search = useUiStore(s => s.search);
  const setSearch = useUiStore(s => s.setSearch);
  const navIdx = useUiStore(s => s.searchNavIdx);
  const navTotal = useUiStore(s => s.searchNavTotal);
  const setNavIdx = useUiStore(s => s.setSearchNavIdx);

  const navigate = (delta: number) => {
    if (navTotal === 0) return;
    setNavIdx(((navIdx + delta) % navTotal + navTotal) % navTotal);
  };

  return (
    <div className="search-bar-row">
      <span style={{ fontSize: 10, color: 'var(--dim)' }}>🔍</span>
      <input
        className="search-bar-input"
        type="text"
        placeholder="Search..."
        value={search}
        onChange={e => setSearch(e.target.value)}
        onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); navigate(e.shiftKey ? -1 : 1); } }}
      />
      {search && navTotal > 0 && (
        <span style={{ fontSize: 10, color: 'var(--dim)', whiteSpace: 'nowrap', fontFamily: "'SF Mono',monospace" }}>
          {navIdx + 1}/{navTotal}
        </span>
      )}
      {search && (
        <>
          <button className="search-nav-btn" onClick={() => navigate(-1)}>▲</button>
          <button className="search-nav-btn" onClick={() => navigate(1)}>▼</button>
          <button className="copy-small" style={{ padding: '2px 6px' }} onClick={() => setSearch('')}>✕</button>
        </>
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

  const [copyLabel, setCopyLabel] = useState('Copy');
  const copyDetail = () => {
    if (!capture) return;
    const data = detailTab === 'response' ? capture.response?.body : capture.body;
    navigator.clipboard.writeText(JSON.stringify(data, null, 2)).then(() => {
      setCopyLabel('✓');
      setTimeout(() => setCopyLabel('Copy'), 1500);
    });
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
          {copyLabel}
        </button>
      </div>
      {capture && detailTab !== 'aiflow' && <MechChipsRow capture={capture} />}
      {capture && (detailTab === 'request' || detailTab === 'response' || detailTab === 'analysis') && <SearchBar />}
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
