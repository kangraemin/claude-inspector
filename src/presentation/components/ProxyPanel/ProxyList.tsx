import { useCaptureStore } from '../../store/captureStore';
import { useUiStore } from '../../store/uiStore';
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
  onClick: () => void;
}

function CaptureEntry({ capture, selected, onClick }: CaptureEntryProps) {
  const ts = new Date(capture.timestamp).toLocaleTimeString('en-US', { hour12: false });
  const color = getSessionColor(capture.sessionId.toString());

  return (
    <div
      className={`prx-entry ${selected ? 'selected' : ''}`}
      onClick={onClick}
    >
      <div style={{ display: 'flex', alignItems: 'center' }}>
        <span className="prx-method">{capture.method}</span>
        <span className="prx-path">{capture.path}</span>
        <span className="prx-ts">{ts}</span>
      </div>
      <div className="prx-model" style={{ color }}>
        session: {capture.sessionId.toString().slice(0, 8)}
        {capture.hasResponse ? ' ✓' : ' …'}
      </div>
    </div>
  );
}

export function ProxyList() {
  const captures = useCaptureStore((s) => s.captures);
  const selectedId = useCaptureStore((s) => s.selectedId);
  const selectCapture = useCaptureStore((s) => s.selectCapture);
  const locale = useUiStore((s) => s.locale);

  return (
    <div className="proxy-list">
      <div className="panel-header">
        <span>{t(locale, 'proxy.capturedRequests')}</span>
      </div>
      <div className="hist-list">
        {captures.length === 0 ? (
          <div className="hist-empty">{t(locale, 'proxy.noCaptures')}</div>
        ) : (
          [...captures].reverse().map((c) => (
            <CaptureEntry
              key={c.id}
              capture={c}
              selected={selectedId === c.id}
              onClick={() => selectCapture(c.id)}
            />
          ))
        )}
      </div>
    </div>
  );
}
