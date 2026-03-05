# v1.1.1 패치 + 온보딩 + 배포

## Context
v1.1.0 이후 잔여 버그 3종 수정, 첫 실행 시 1회 온보딩 웰컴 모달 추가, v1.1.1 배포.
이전에 clipboard .catch() + fs.readFileSync try/catch 이미 수정됨.

## 구조 파악
- `SHOW_SIMULATOR = false` → Proxy 패널이 기본 초기 화면
- `i18n` 객체: `LOCALES[locale][key]` 구조, `applyI18n()`이 `[data-i18n]` 속성 자동 갱신
- `localStorage`: `ci-lang`, `ci-api-key` 사용 중 → `ci-onboarded` 키 추가

---

## Phase 1: main.js 버그 수정

### Step 1: 포트 검증 + JSON.parse 로깅 (main.js)

**1-A** `proxy-start` 핸들러 (~line 125) 진입부:
```js
ipcMain.handle('proxy-start', (_event, port = 9090) => {
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    return { error: 'Invalid port: must be 1–65535' };
  }
  if (proxyServer) ...
```

**1-B** 요청 body JSON.parse catch (~line 135):
```js
try { bodyObj = JSON.parse(bodyBuf.toString()); } catch (e) { console.warn('req body parse failed:', e.message); }
```

**1-C** 응답 body JSON.parse catch (~line 160):
```js
try { respObj = JSON.parse(respStr); } catch { /* SSE stream — JSON.parse expected to fail */ }
```

---

## Phase 2: index.html 버그 수정

### Step 2: modelSel optional chaining 3곳

**2-A** `buildPayload()` (~line 1464):
```js
const model = document.getElementById('modelSel')?.value || 'claude-sonnet-4-6';
```

**2-B** `buildSendablePayload()` (~line 1526): 동일 패턴

**2-C** `addEventListener` (~line 3038):
```js
document.getElementById('modelSel')?.addEventListener('change', updatePreview);
```

---

## Phase 3: 온보딩 웰컴 모달 (index.html)

### Step 3-A: LOCALES 키 추가 (ko + en 양쪽)

위치: 기존 LOCALES 객체 내 ko/en 각각에 추가

```js
// ko
onboard: {
  title: 'Claude Inspector 시작하기',
  sub: 'Claude Code가 API에 실제로 보내는 내용을 실시간으로 확인하세요',
  step1: '아래 <b>Start Proxy</b> 버튼 클릭 → 로컬 프록시(localhost:9090) 시작',
  step2: '새 터미널을 열고 아래 명령어로 Claude Code 실행:',
  step3: '이 화면으로 돌아와 <b>Messages</b> · <b>Request</b> · <b>Analysis</b> 탭에서 캡처된 트래픽 확인',
  note: '💡 프록시는 로컬에서만 동작합니다. 외부로 데이터가 전송되지 않습니다.',
  btn: '시작하기 →',
}

// en
onboard: {
  title: 'Getting Started',
  sub: 'See what Claude Code actually sends to the Anthropic API — in real-time',
  step1: 'Click <b>Start Proxy</b> below — starts a local proxy on localhost:9090',
  step2: 'Open a new terminal and run Claude Code through the proxy:',
  step3: 'Come back here and browse captured traffic in <b>Messages</b> · <b>Request</b> · <b>Analysis</b>',
  note: '💡 The proxy runs locally only. No data is sent anywhere except directly to api.anthropic.com.',
  btn: 'Get Started →',
}
```

### Step 3-B: HTML 모달 추가 (body 안, 기존 div 위)

```html
<div id="onboardModal" class="onboard-overlay" style="display:none">
  <div class="onboard-card">
    <div class="onboard-title" data-i18n="onboard.title"></div>
    <div class="onboard-sub" data-i18n="onboard.sub"></div>
    <ol class="onboard-steps">
      <li data-i18n-html="onboard.step1"></li>
      <li>
        <span data-i18n-html="onboard.step2"></span>
        <code class="onboard-cmd">ANTHROPIC_BASE_URL=http://localhost:9090 claude</code>
      </li>
      <li data-i18n-html="onboard.step3"></li>
    </ol>
    <div class="onboard-note" data-i18n="onboard.note"></div>
    <button class="onboard-btn" onclick="closeOnboard()" data-i18n="onboard.btn"></button>
  </div>
</div>
```

### Step 3-C: CSS 추가 (기존 style 블록 내)

```css
.onboard-overlay {
  position: fixed; inset: 0; z-index: 1000;
  background: rgba(0,0,0,.6); backdrop-filter: blur(4px);
  display: flex; align-items: center; justify-content: center;
}
.onboard-card {
  background: var(--bg1); border: 1px solid var(--border);
  border-radius: 16px; padding: 36px 40px; max-width: 480px; width: 90%;
}
.onboard-title { font-size: 1.3rem; font-weight: 700; margin-bottom: 8px; }
.onboard-sub { color: var(--fg2); margin-bottom: 24px; font-size: .9rem; }
.onboard-steps { padding-left: 20px; display: flex; flex-direction: column; gap: 12px;
  color: var(--fg1); font-size: .9rem; margin-bottom: 28px; }
.onboard-cmd { display: block; margin-top: 6px; background: var(--bg2);
  border: 1px solid var(--border); border-radius: 6px; padding: 8px 12px;
  font-family: monospace; font-size: .85rem; color: var(--accent); user-select: all; }
.onboard-btn {
  width: 100%; padding: 12px; border-radius: 8px;
  background: var(--accent); color: #fff; border: none;
  font-size: 1rem; font-weight: 600; cursor: pointer;
}
.onboard-btn:hover { opacity: .9; }
.onboard-note { font-size: .8rem; color: var(--fg2); margin-bottom: 16px; }
```

### Step 3-D: JS 추가

```js
function closeOnboard() {
  document.getElementById('onboardModal').style.display = 'none';
  localStorage.setItem('ci-onboarded', '1');
}

// 초기화 로직 (기존 switchM('proxy') 호출 근처)에 추가:
if (!localStorage.getItem('ci-onboarded')) {
  document.getElementById('onboardModal').style.display = 'flex';
}
```

---

## Phase 4: 버전 업 + 배포

### Step 4-1: package.json 1.1.0 → 1.1.1

### Step 4-2: npm run dist:mac

### Step 4-3: gh release create v1.1.1 + README 다운로드 링크 업데이트

---

## Verification
```bash
npm run test:unit && npm run test:e2e   # 25개 E2E 통과
```
수동:
- `localStorage.removeItem('ci-onboarded')` 후 앱 재시작 → 모달 표시
- 언어 전환 시 모달 텍스트 변경 확인
- "시작하기" 클릭 → 모달 사라짐, ci-onboarded 키 저장
- 재시작 후 모달 미표시

## 파일
- `main.js`
- `public/index.html`
- `package.json`
- `README.md`, `README.ko.md` (다운로드 링크 v1.1.1)
