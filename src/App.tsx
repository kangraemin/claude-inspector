import { useElectronEvents } from './presentation/hooks/useElectronEvents';

function AppInner() {
  useElectronEvents();
  // Phase 6에서 UI 컴포넌트 추가 예정
  return (
    <div id="app-root">
      {/* Components will be added in Phase 6 */}
    </div>
  );
}

export default function App() {
  return <AppInner />;
}
