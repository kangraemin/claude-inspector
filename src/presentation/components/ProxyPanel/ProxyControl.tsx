import { useState, useRef } from 'react';
import { useProxy } from '../../hooks/useProxy';
import { useCaptureStore } from '../../store/captureStore';
import { useUiStore } from '../../store/uiStore';
import { t } from '../../../i18n';
import { Spinner } from '../shared/Spinner';

export function ProxyControl() {
  const [loading, setLoading] = useState(false);
  const portRef = useRef<HTMLInputElement>(null);
  const { start, stop } = useProxy();
  const proxyRunning = useCaptureStore((s) => s.proxyRunning);
  const proxyPort = useCaptureStore((s) => s.proxyPort);
  const clear = useCaptureStore((s) => s.clear);
  const locale = useUiStore((s) => s.locale);

  const toggle = async () => {
    setLoading(true);
    try {
      if (proxyRunning) {
        await stop();
      } else {
        const port = parseInt(portRef.current?.value || '9090') || 9090;
        const result = await start(port);
        if (portRef.current && result.port) {
          portRef.current.value = String(result.port);
        }
      }
    } finally {
      setLoading(false);
    }
  };

  const displayPort = proxyPort ?? parseInt(portRef.current?.value || '9090') ?? 9090;
  const cmd = proxyRunning
    ? `ANTHROPIC_BASE_URL=http://localhost:${displayPort} claude`
    : t(locale, 'proxy.startFirst');

  const copyCmd = () => {
    if (proxyRunning) navigator.clipboard.writeText(cmd);
  };

  return (
    <div className="proxy-ctrl">
      <div className="panel-header">
        <span>{t(locale, 'proxy.title')}</span>
        <span className="inject-chip" style={{ color: 'var(--red)', borderColor: 'rgba(244,135,113,.3)', background: 'rgba(244,135,113,.08)' }}>
          {t(locale, 'proxy.liveCapture')}
        </span>
      </div>
      <div className="config-body">
        <div className="how-box" style={{ borderColor: 'rgba(244,135,113,.25)', background: 'rgba(244,135,113,.04)' }}>
          <div className="how-title" style={{ color: 'var(--red)' }}>⚡ {t(locale, 'proxy.interceptTitle')}</div>
          <div className="how-text" style={{ fontSize: 11, color: 'var(--dim)', lineHeight: 1.6, marginTop: 4 }}>
            {t(locale, 'proxy.interceptDesc')}
          </div>
        </div>
        <div className="field">
          <label>{t(locale, 'proxy.port')}</label>
          <input
            ref={portRef}
            type="number"
            defaultValue={9090}
            min={1024}
            max={65535}
            disabled={proxyRunning}
            style={{ width: 120 }}
          />
        </div>
        <div className={`proxy-status ${proxyRunning ? 'running' : ''}`}>
          <span className="ps-dot" />
          <span>
            {proxyRunning
              ? t(locale, 'proxy.running', { port: displayPort })
              : t(locale, 'proxy.stopped')}
          </span>
        </div>
        <div className="field">
          <label style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <span>{t(locale, 'proxy.runCommand')}</span>
            {proxyRunning && (
              <button className="copy-small" onClick={copyCmd} style={{ textTransform: 'none', letterSpacing: 0, fontWeight: 'normal' }}>
                {t(locale, 'copy.copy')}
              </button>
            )}
          </label>
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
        <button className="btn btn-copy" onClick={clear}>
          {t(locale, 'proxy.clear')}
        </button>
      </div>
    </div>
  );
}
