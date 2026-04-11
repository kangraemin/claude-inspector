import { useState } from 'react';
import { useProxy } from '../../hooks/useProxy';
import { useCaptureStore } from '../../store/captureStore';
import { useUiStore } from '../../store/uiStore';
import { t } from '../../../i18n';
import { Spinner } from '../shared/Spinner';

export function ProxyControl() {
  const [loading, setLoading] = useState(false);
  const { start, stop } = useProxy();
  const proxyRunning = useCaptureStore((s) => s.proxyRunning);
  const proxyPort = useCaptureStore((s) => s.proxyPort);
  const locale = useUiStore((s) => s.locale);

  const toggle = async () => {
    setLoading(true);
    try {
      if (proxyRunning) {
        await stop();
      } else {
        await start();
      }
    } finally {
      setLoading(false);
    }
  };

  const cmd = proxyRunning
    ? `ANTHROPIC_BASE_URL=http://localhost:${proxyPort ?? 9090} claude`
    : t(locale, 'proxy.startFirst');

  return (
    <div className="proxy-ctrl">
      <div className="panel-header">
        <span>{t(locale, 'proxy.title')}</span>
        <span className="inject-chip" style={{ color: 'var(--red)', borderColor: 'rgba(244,135,113,.3)', background: 'rgba(244,135,113,.08)' }}>
          {t(locale, 'proxy.liveCapture')}
        </span>
      </div>
      <div className="config-body">
        <div className={`proxy-status ${proxyRunning ? 'running' : ''}`}>
          <span className="ps-dot" />
          <span>
            {proxyRunning
              ? t(locale, 'proxy.running', { port: proxyPort ?? 9090 })
              : t(locale, 'proxy.stopped')}
          </span>
        </div>
        <div className="field">
          <label>{t(locale, 'proxy.runCommand')}</label>
          <div className="proxy-cmd">{cmd}</div>
        </div>
      </div>
      <div className="config-footer">
        <button
          className="btn btn-send"
          onClick={toggle}
          disabled={loading}
          style={{ flex: 1, justifyContent: 'center' }}
        >
          {loading && <Spinner size={12} color="#fff" />}
          {proxyRunning ? t(locale, 'proxy.stopProxy') : t(locale, 'proxy.startProxy')}
        </button>
      </div>
    </div>
  );
}
