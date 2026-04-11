import './styles/index.css';
import { useState, useEffect } from 'react';
import { useElectronEvents } from './presentation/hooks/useElectronEvents';
import { Header } from './presentation/components/Header/Header';
import { ProxyControl } from './presentation/components/ProxyPanel/ProxyControl';
import { ProxyList } from './presentation/components/ProxyPanel/ProxyList';
import { ProxyDetail } from './presentation/components/ProxyDetail/ProxyDetail';
import { useUiStore } from './presentation/store/uiStore';

function OnboardingModal({ onClose }: { onClose: () => void }) {
  return (
    <div className="onboard-overlay">
      <div className="onboard-card">
        <div className="onboard-title">Claude Inspector 시작하기</div>
        <div className="onboard-sub">Claude Code API 요청을 실시간으로 시각화합니다</div>
        <ol className="onboard-steps">
          <li>왼쪽 패널에서 <b>Start Proxy</b> 클릭</li>
          <li>새 터미널에서 명령 실행:
            <code className="onboard-cmd">ANTHROPIC_BASE_URL=http://localhost:9090 claude</code>
          </li>
          <li>Claude Code를 사용하면 요청이 자동으로 캡처됩니다</li>
        </ol>
        <div className="onboard-note">※ 프록시 없이 바로 사용해도 됩니다</div>
        <button className="onboard-btn" onClick={onClose}>시작하기</button>
      </div>
    </div>
  );
}

function AppInner() {
  useElectronEvents();
  const [onboarded, setOnboarded] = useState(() => !!localStorage.getItem('ci-onboarded'));

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'f') {
        e.preventDefault();
        document.querySelector<HTMLInputElement>('.search-bar-input')?.focus();
      }
      if (e.key === 'Escape') {
        useUiStore.getState().setSearch('');
        useUiStore.getState().setMechFilter(null);
      }
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, []);

  return (
    <>
      {!onboarded && (
        <OnboardingModal onClose={() => {
          localStorage.setItem('ci-onboarded', '1');
          setOnboarded(true);
        }} />
      )}
      <Header />
      <div className="main">
        <div className="proxy-panel">
          <ProxyControl />
          <div className="proxy-stream">
            <ProxyList />
            <ProxyDetail />
          </div>
        </div>
      </div>
    </>
  );
}

export default function App() {
  return <AppInner />;
}
