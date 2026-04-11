import { useUiStore } from '../../store/uiStore';
import { t } from '../../../i18n';

export function Header() {
  const locale = useUiStore((s) => s.locale);
  const setLocale = useUiStore((s) => s.setLocale);

  return (
    <header className="header">
      <div className="logo">
        <div className="logo-icon">CI</div>
        <span className="logo-text">Claude Inspector</span>
        <span className="logo-sub">{t(locale, 'header.logoSub')}</span>
      </div>
      <div className="header-right">
        <button
          className="copy-small"
          onClick={() => setLocale(locale === 'ko' ? 'en' : 'ko')}
        >
          {locale === 'ko' ? 'EN' : 'KO'}
        </button>
      </div>
    </header>
  );
}
