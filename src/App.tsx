import './styles/index.css';
import { useElectronEvents } from './presentation/hooks/useElectronEvents';
import { Header } from './presentation/components/Header/Header';
import { ProxyControl } from './presentation/components/ProxyPanel/ProxyControl';
import { ProxyList } from './presentation/components/ProxyPanel/ProxyList';
import { ProxyDetail } from './presentation/components/ProxyDetail/ProxyDetail';
import { AiFlowPanel } from './presentation/components/AiFlow/AiFlowPanel';

function AppInner() {
  useElectronEvents();

  return (
    <>
      <Header />
      <div className="main">
        <div className="proxy-panel">
          <ProxyControl />
          <div className="proxy-stream">
            <ProxyList />
            <ProxyDetail />
          </div>
        </div>
        <div style={{
          width: 420,
          flexShrink: 0,
          background: 'var(--surface)',
          borderLeft: '1px solid var(--border)',
          display: 'flex',
          flexDirection: 'column',
          overflow: 'hidden',
        }}>
          <AiFlowPanel />
        </div>
      </div>
    </>
  );
}

export default function App() {
  return <AppInner />;
}
