import { useState } from 'react';
import { useCaptureStore } from '../../store/captureStore';
import { useUiStore } from '../../store/uiStore';
import { useAiflowStore } from '../../store/aiflowStore';
import { t } from '../../../i18n';
import type { ProxyCapture } from '../../../domain/entities/ProxyCapture';

function getSessionColor(sessionId: string): string {
  const colors = ['#569cd6', '#4ec9b0', '#dcdcaa', '#c586c0', '#ce9178', '#f48771'];
  let hash = 0;
  for (let i = 0; i < sessionId.length; i++) {
    hash = (hash * 31 + sessionId.charCodeAt(i)) & 0xffffffff;
  }
  return colors[Math.abs(hash) % colors.length];
}

interface CaptureEntryProps {
  capture: ProxyCapture;
  selected: boolean;
  showCheck: boolean;
  checked: boolean;
  onSelect: () => void;
  onCheck: (e: React.MouseEvent) => void;
}

function CaptureEntry({ capture, selected, showCheck, checked, onSelect, onCheck }: CaptureEntryProps) {
  const color = getSessionColor(capture.sessionId.toString());
  const status = capture.response as { status?: number } | undefined;
  const statusCode = status?.status;
  const model = (capture.body as { model?: string } | null)?.model;

  const statusEl = statusCode != null ? (
    <span style={{ fontSize: 10, fontFamily: "'SF Mono', monospace", flexShrink: 0, color: statusCode < 400 ? 'var(--green)' : 'var(--red)' }}>
      {statusCode}
    </span>
  ) : (
    <span style={{ fontSize: 10, color: 'var(--dim)', flexShrink: 0 }}>…</span>
  );

  return (
    <div
      className={`prx-entry${selected ? ' selected' : ''}${showCheck && checked ? ' aiflow-checked' : ''}`}
      style={{ borderLeft: `3px solid ${color}` }}
      onClick={onSelect}
    >
      <div style={{ display: 'flex', alignItems: 'center', overflow: 'hidden' }}>
        {showCheck && (
          <input
            type="checkbox"
            checked={checked}
            onClick={onCheck}
            onChange={() => {}}
            style={{ marginRight: 6, flexShrink: 0 }}
          />
        )}
        <span className="prx-method">{capture.method}</span>
        <span className="prx-path">{capture.path}</span>
        {statusEl}
        <span className="prx-ts">{capture.timestamp}</span>
      </div>
      {model && <div className="prx-model">{model}</div>}
    </div>
  );
}

export function ProxyList() {
  const [saveLabel, setSaveLabel] = useState('Save');
  const captures = useCaptureStore((s) => s.captures);
  const selectedId = useCaptureStore((s) => s.selectedId);
  const selectCapture = useCaptureStore((s) => s.selectCapture);
  const locale = useUiStore((s) => s.locale);
  const detailTab = useUiStore((s) => s.detailTab);

  const selectedCaptureIds = useAiflowStore((s) => s.selectedCaptureIds);
  const toggleCaptureSelection = useAiflowStore((s) => s.toggleCaptureSelection);
  const selectAllCaptures = useAiflowStore((s) => s.selectAllCaptures);
  const deselectAllCaptures = useAiflowStore((s) => s.deselectAllCaptures);
  const lastCheckedId = useAiflowStore((s) => s.lastCheckedId);
  const setLastCheckedId = useAiflowStore((s) => s.setLastCheckedId);

  const showCheck = detailTab === 'aiflow';
  const allSelected = captures.length > 0 && captures.every((c) => selectedCaptureIds.has(c.id));

  const handleSelectAll = () => {
    if (allSelected) deselectAllCaptures();
    else selectAllCaptures(captures.map((c) => c.id));
  };

  const handleSave = async () => {
    if (!window.electronAPI || captures.length === 0) return;
    const now = new Date().toISOString().slice(0, 10);
    const sessionMap = new Map<string, typeof captures>();
    for (const c of captures) {
      const sid = c.sessionId?.toString() ?? 'default';
      if (!sessionMap.has(sid)) sessionMap.set(sid, []);
      sessionMap.get(sid)!.push(c);
    }
    if (sessionMap.size > 1 && (window.electronAPI as any).exportCaptureSessions) {
      const payload = [...sessionMap.entries()].map(([sid, caps], i) => ({
        filename: `claude-inspector-s${i + 1}-${sid.slice(0, 6)}-${now}.json`,
        data: JSON.stringify(caps, null, 2),
      }));
      const result = await (window.electronAPI as any).exportCaptureSessions(payload);
      if (!result.canceled) {
        setSaveLabel('Saved!');
        setTimeout(() => setSaveLabel('Save'), 1200);
      }
    } else {
      const result = await window.electronAPI.exportCaptures({
        data: JSON.stringify(captures, null, 2),
        defaultName: `claude-inspector-${now}.json`,
      });
      if (result.saved) {
        setSaveLabel('Saved!');
        setTimeout(() => setSaveLabel('Save'), 1200);
      }
    }
  };

  return (
    <div className="proxy-list">
      <div className="panel-header">
        <span>{t(locale, 'proxy.capturedRequests')}</span>
        <span style={{ fontSize: 10, color: 'var(--dim)' }}>{captures.length}</span>
        <div style={{ marginLeft: 'auto', display: 'flex', gap: 4 }}>
          <button className="copy-small" onClick={handleSave} title="캡처를 JSON 파일로 저장">
            {saveLabel}
          </button>
        </div>
      </div>

      {showCheck && captures.length > 0 && (
        <div style={{ padding: '4px 13px', borderBottom: '1px solid var(--border)', display: 'flex', alignItems: 'center', gap: 6 }}>
          <input type="checkbox" checked={allSelected} onChange={handleSelectAll} />
          <span style={{ fontSize: 10, color: 'var(--dim)' }}>
            {allSelected
              ? t(locale, 'aiflow.deselectAll')
              : t(locale, 'aiflow.selectAll')}
          </span>
        </div>
      )}

      <div className="hist-list">
        {captures.length === 0 ? (
          <div className="hist-empty" dangerouslySetInnerHTML={{ __html: t(locale, 'proxy.noCaptures') }} />
        ) : (
          [...captures].reverse().map((c) => (
            <CaptureEntry
              key={c.id}
              capture={c}
              selected={selectedId === c.id}
              showCheck={showCheck}
              checked={selectedCaptureIds.has(c.id)}
              onSelect={() => selectCapture(c.id)}
              onCheck={(e) => {
                e.stopPropagation();
                const id = c.id;
                if (e.shiftKey && lastCheckedId !== null) {
                  const ids = [...captures].sort((a, b) => a.id - b.id).map(x => x.id);
                  const from = ids.indexOf(lastCheckedId), to = ids.indexOf(id);
                  if (from >= 0 && to >= 0) {
                    const [s, e2] = [Math.min(from, to), Math.max(from, to)];
                    selectAllCaptures(ids.slice(s, e2 + 1));
                  }
                } else {
                  toggleCaptureSelection(id);
                }
                setLastCheckedId(id);
              }}
            />
          ))
        )}
      </div>
    </div>
  );
}
