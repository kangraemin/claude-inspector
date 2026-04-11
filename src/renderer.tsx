import React, { useMemo } from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import { DIProvider, createContainer } from './presentation/di/container';

function Root() {
  const container = useMemo(() => createContainer(), []);
  return (
    <DIProvider value={container}>
      <App />
    </DIProvider>
  );
}

if (window.electronAPI?.platform === 'darwin') {
  document.body.classList.add('darwin');
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <Root />
  </React.StrictMode>
);
