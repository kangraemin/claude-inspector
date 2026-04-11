# Step 3: App 최상위 구조

## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-01 | renderer.tsx — DIProvider + createContainer() 초기화 | 앱 엔트리 DI 주입 | ✅ |
| TC-02 | App.tsx — DIProvider 하위에 ElectronEvents 훅 마운트 | useElectronEvents 호출 | ✅ |
| TC-03 | npx tsc --noEmit 에러 없음 | exit 0 | ✅ |

검증 명령어:
```bash
cat src/renderer.tsx
npx tsc --noEmit && echo "tsc OK"
```

## 실행출력

```
$ cat src/renderer.tsx
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

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <Root />
  </React.StrictMode>
);

$ npx tsc --noEmit && echo "tsc OK"
tsc OK
```

TC-01 ✅ renderer.tsx — DIProvider + createContainer() 초기화
TC-02 ✅ App.tsx — useElectronEvents 호출 (AppInner)
TC-03 ✅ tsc --noEmit → exit 0
