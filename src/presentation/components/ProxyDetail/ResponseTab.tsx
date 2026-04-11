import { JsonTree } from '../shared/JsonTree';
import { useUiStore } from '../../store/uiStore';
import { t } from '../../../i18n';
import type { ProxyCapture } from '../../../domain/entities/ProxyCapture';

interface Props {
  capture: ProxyCapture;
}

export function ResponseTab({ capture }: Props) {
  const locale = useUiStore((s) => s.locale);

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
      {capture.response.body != null ? (
        <JsonTree data={capture.response.body} />
      ) : (
        <div className="proxy-empty">{t(locale, 'proxy.noBody')}</div>
      )}
    </div>
  );
}
