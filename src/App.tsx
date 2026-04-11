import './styles/index.css';
import { useElectronEvents } from './presentation/hooks/useElectronEvents';
import { Header } from './presentation/components/Header/Header';
import { ProxyControl } from './presentation/components/ProxyPanel/ProxyControl';
import { ProxyList } from './presentation/components/ProxyPanel/ProxyList';
import { ProxyDetail } from './presentation/components/ProxyDetail/ProxyDetail';

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
      </div>
    </>
  );
}

export default function App() {
  return <AppInner />;
}
