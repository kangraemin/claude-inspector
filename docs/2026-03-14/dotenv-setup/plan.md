# dotenv 추가하여 .env 자동 로드

## 변경 파일별 상세

### `main.js`
- **변경 이유**: Sentry.init() 전에 dotenv를 로드해야 SENTRY_DSN 환경변수가 반영됨
- **Before** (현재 코드):
```javascript
const Sentry = require('@sentry/electron/main');
Sentry.init({
  dsn: process.env.SENTRY_DSN || '',
```
- **After** (변경 후):
```javascript
require('dotenv').config();
const Sentry = require('@sentry/electron/main');
Sentry.init({
  dsn: process.env.SENTRY_DSN || '',
```
- **영향 범위**: .env 파일의 모든 환경변수가 process.env에 로드됨

### `package.json`
- **변경 이유**: dotenv 의존성 추가 + electron-builder files에 포함
- **Before**:
```json
"dependencies": {
  "@anthropic-ai/sdk": "^0.78.0",
  "@sentry/electron": "^7.10.0"
}
```
- **After**:
```json
"dependencies": {
  "@anthropic-ai/sdk": "^0.78.0",
  "@sentry/electron": "^7.10.0",
  "dotenv": "^16.4.7"
}
```
- build.files에 `"node_modules/dotenv/**"` 추가

## 검증
- 검증 명령어: `node -e "require('./main.js')"` 는 Electron 전용이므로 불가
- 대안: `node --check main.js` (구문 검증) + `npm start`로 부팅 확인
- 기대 결과: 정상 부팅, .env의 SENTRY_DSN이 로드됨
