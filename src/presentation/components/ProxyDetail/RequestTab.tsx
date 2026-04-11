import { useMemo } from 'react';
import { JsonTree } from '../shared/JsonTree';
import { useUiStore } from '../../store/uiStore';
import { t } from '../../../i18n';
import { ResponseParserService } from '../../../domain/services/ResponseParserService';
import type { ProxyCapture } from '../../../domain/entities/ProxyCapture';

const parser = new ResponseParserService();

interface Props {
  capture: ProxyCapture;
}

export function RequestTab({ capture }: Props) {
  const locale = useUiStore((s) => s.locale);
  const search = useUiStore((s) => s.search);
  const mechFilter = useUiStore((s) => s.mechFilter);
  const navIdx = useUiStore((s) => s.searchNavIdx);
  const setNavTotal = useUiStore((s) => s.setSearchNavTotal);
  const detection = useMemo(() => parser.detectMechanisms(capture.body), [capture.body]);

  return (
    <div style={{ flex: 1, overflow: 'auto' }}>
      <div style={{ padding: '8px 12px', fontSize: 11, color: 'var(--dim)', borderBottom: '1px solid var(--border)' }}>
        <span style={{ color: 'var(--green)', fontWeight: 700 }}>{capture.method}</span>
        {' '}
        <span>{capture.path}</span>
      </div>
      {capture.body ? (
        <JsonTree data={capture.body} search={search || undefined} mechKey={mechFilter} navIdx={navIdx} onMatchTotal={setNavTotal} mechDetection={detection} />
      ) : (
        <div className="proxy-empty">{t(locale, 'proxy.noBody')}</div>
      )}
    </div>
  );
}
