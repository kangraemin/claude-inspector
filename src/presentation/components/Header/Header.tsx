import { useState, useEffect } from 'react';
import { useUiStore } from '../../store/uiStore';
import { t } from '../../../i18n';

export function Header() {
  const locale = useUiStore((s) => s.locale);
  const setLocale = useUiStore((s) => s.setLocale);
  const [version, setVersion] = useState('');
  const [updateReady, setUpdateReady] = useState(false);

  useEffect(() => {
    fetch('build-info.json').then(r => r.json())
      .then(d => setVersion(`v${d.version} (${d.hash})`))
      .catch(() => {});
    (window as any).electronAPI?.onUpdateAvailable?.(() => setUpdateReady(true));
  }, []);

  return (
    <header className="header">
      <div className="logo">
        <div className="logo-icon">CI</div>
        <span className="logo-text">Claude Inspector</span>
        <span className="logo-sub">{t(locale, 'header.logoSub')}</span>
        {version && <span className="logo-ver">{version}</span>}
      </div>
      <div className="header-right">
        {updateReady && (
          <button className="update-badge" style={{ display: 'block' }}
            onClick={() => (window as any).electronAPI?.installUpdate?.()}>
            Update
          </button>
        )}
        <button className="copy-small" onClick={() => setLocale(locale === 'ko' ? 'en' : 'ko')}>
          {locale === 'ko' ? 'EN' : 'KO'}
        </button>
      </div>
    </header>
  );
}
