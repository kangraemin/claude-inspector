# Start Proxy 버튼 무반응 수정

## 변경 파일별 상세
### `preload.js`
- **변경 이유**: Sentry renderer init 실패가 전체 preload를 죽이지 않도록 방어
- **Before** (현재 코드):
```javascript
require('@sentry/electron/renderer').init();

const { contextBridge, ipcRenderer } = require('electron');
```
- **After** (변경 후):
```javascript
try { require('@sentry/electron/renderer').init(); } catch {}

const { contextBridge, ipcRenderer } = require('electron');
```
- **영향 범위**: Sentry renderer 초기화 실패 시에도 electronAPI가 정상 노출됨

## 검증
- 검증 명령어: `npm start` → Start Proxy 버튼 클릭
- 기대 결과: 프록시 시작, 상태 "포트 9090에서 실행 중" 표시
