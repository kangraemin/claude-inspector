import { JsonTree } from '../shared/JsonTree';
import { useUiStore } from '../../store/uiStore';
import { t } from '../../../i18n';
import type { ProxyCapture } from '../../../domain/entities/ProxyCapture';

interface Props {
  capture: ProxyCapture;
}

export function RequestTab({ capture }: Props) {
  const locale = useUiStore((s) => s.locale);

  return (
    <div style={{ flex: 1, overflow: 'auto' }}>
      <div style={{ padding: '8px 12px', fontSize: 11, color: 'var(--dim)', borderBottom: '1px solid var(--border)' }}>
        <span style={{ color: 'var(--green)', fontWeight: 700 }}>{capture.method}</span>
        {' '}
        <span>{capture.path}</span>
      </div>
      {capture.body ? (
        <JsonTree data={capture.body} />
      ) : (
        <div className="proxy-empty">{t(locale, 'proxy.noBody')}</div>
      )}
    </div>
  );
}
