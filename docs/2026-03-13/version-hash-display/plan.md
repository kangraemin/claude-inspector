# 빌드 버전 해시 표시

## 변경 파일별 상세

### `package.json`
- **변경 이유**: `dist` 스크립트 실행 전에 git hash를 `public/build-info.json`에 기록하는 prebuild 단계 추가
- **Before** (현재 코드):
```json
"dist": "electron-builder",
```
- **After** (변경 후):
```json
"predist": "node -e \"const {execSync}=require('child_process');const fs=require('fs');const hash=execSync('git rev-parse --short HEAD').toString().trim();const pkg=require('./package.json');fs.writeFileSync('public/build-info.json',JSON.stringify({version:pkg.version,hash,built:new Date().toISOString()}))\"",
"dist": "electron-builder",
```
- **영향 범위**: `npm run dist` 실행 시에만 동작. `npm start`에서는 build-info.json 없으면 fallback.

### `public/index.html`
- **변경 이유**: 헤더 로고 옆에 버전+해시 표시
- **Before** (현재 코드):
```html
<span class="logo-sub" data-i18n="header.logoSub">Prompt Mechanism Visualizer</span>
```
- **After** (변경 후):
```html
<span class="logo-sub" data-i18n="header.logoSub">Prompt Mechanism Visualizer</span>
<span class="logo-ver" id="buildVer"></span>
```

CSS 추가:
```css
.logo-ver { font-size: 10px; color: var(--dim); opacity: 0.6; }
```

JS (하단 초기화 부분):
```js
fetch('build-info.json').then(r=>r.json()).then(b=>{
  document.getElementById('buildVer').textContent = `v${b.version} (${b.hash})`;
}).catch(()=>{});
```
- **영향 범위**: 헤더 로고 영역. build-info.json 없으면(개발 모드) 빈 상태로 유지.

### `public/build-info.json` (신규, 빌드 시 자동 생성)
- **용도**: 빌드 메타데이터 (version, hash, built timestamp)
- `.gitignore`에 추가하여 git 추적 안 함

### `.gitignore`
- **변경 이유**: 빌드 시 자동 생성되는 파일 제외
- `public/build-info.json` 한 줄 추가

## 검증
- 검증 명령어: `npm run predist && cat public/build-info.json`
- 기대 결과: `{"version":"1.1.3","hash":"<7자리>","built":"<ISO timestamp>"}` 출력
