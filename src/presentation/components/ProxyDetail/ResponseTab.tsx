import { JsonTree } from '../shared/JsonTree';
import { useUiStore } from '../../store/uiStore';
import { t } from '../../../i18n';
import type { ProxyCapture } from '../../../domain/entities/ProxyCapture';

interface Props {
  capture: ProxyCapture;
}

function TokenInfoRow({ body }: { body: unknown }) {
  const usage = (body as any)?.usage;
  if (!usage) return null;
  const totalIn = usage.input_tokens ?? 0;
  const out = usage.output_tokens ?? 0;
  const cacheRead = usage.cache_read_input_tokens ?? 0;
  const cacheWrite = usage.cache_creation_input_tokens ?? 0;
  const cacheHit = totalIn > 0 ? Math.round(cacheRead / totalIn * 100) : 0;
  return (
    <div className="token-info-row">
      <span className="tt-badge blue">in {totalIn.toLocaleString()}</span>
      <span className="tt-badge">out {out.toLocaleString()}</span>
      {cacheRead > 0 && <span className="tt-badge green">cache_read {cacheRead.toLocaleString()} ({cacheHit}%)</span>}
      {cacheWrite > 0 && <span className="tt-badge yellow">cache_write {cacheWrite.toLocaleString()}</span>}
    </div>
  );
}

export function ResponseTab({ capture }: Props) {
  const locale = useUiStore((s) => s.locale);
  const search = useUiStore((s) => s.search);
  const mechFilter = useUiStore((s) => s.mechFilter);

  if (!capture.response) {
    return (
      <div className="proxy-empty">{t(locale, 'proxy.waitingResponse')}</div>
    );
  }

  return (
    <div style={{ flex: 1, overflow: 'auto' }}>
      <div style={{ padding: '8px 12px', fontSize: 11, color: 'var(--dim)', borderBottom: '1px solid var(--border)' }}>
        <span>Status: </span>
        <span style={{ color: capture.response.status >= 400 ? 'var(--red)' : 'var(--green)', fontWeight: 700 }}>
          {capture.response.status}
        </span>
      </div>
      <TokenInfoRow body={capture.response.body} />
      {capture.response.body != null ? (
        <JsonTree data={capture.response.body} search={search || undefined} mechKey={mechFilter} />
      ) : (
        <div className="proxy-empty">{t(locale, 'proxy.noBody')}</div>
      )}
    </div>
  );
}
