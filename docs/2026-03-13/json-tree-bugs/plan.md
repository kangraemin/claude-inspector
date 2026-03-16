# JSON 트리 버그 2건 + 토큰 설명 추가

## Context
JSON 트리 뷰어에서 두 가지 UI 버그 + 토큰 설명 부재:
1. 노드 접었을 때 줄 번호가 업데이트되지 않음 (접힌 줄도 카운트)
2. CLAUDE.md 칩 클릭 시 표시 깨짐
3. 접힌 노드에 토큰 수 미표시
4. Request 토큰 배지에 실제 사용량(input/output) 미표시

## 변경 파일별 상세

### `public/index.html`

#### Bug 1: 접힌 노드 줄 번호

- **변경 이유**: CSS counter가 `display:none` 부모 안의 `.jt-row`를 여전히 카운트하는 문제. 접힌 자식 row에 `counter-increment: none`을 명시적으로 적용해야 함.
- **Before** (CSS, 라인 613):
```css
.jt-lined .jt-row { counter-increment: jt-line; }
```
- **After** (CSS):
```css
.jt-lined .jt-row { counter-increment: jt-line; }
.jt-lined .jt-row.jt-no-count { counter-increment: none; }
```

- **Before** (JS, 라인 1724-1732):
```javascript
function jtToggle(id) {
  const body = document.getElementById(`${id}-b`);
  const summary = document.getElementById(`${id}-s`);
  const btn = document.getElementById(`${id}-btn`);
  const open = body.style.display !== 'none';
  body.style.display = open ? 'none' : '';
  summary.style.display = open ? '' : 'none';
  btn.textContent = open ? '▶' : '▼';
}
```
- **After**:
```javascript
function jtToggle(id) {
  const body = document.getElementById(`${id}-b`);
  const summary = document.getElementById(`${id}-s`);
  const btn = document.getElementById(`${id}-btn`);
  const open = body.style.display !== 'none';
  body.style.display = open ? 'none' : '';
  body.querySelectorAll('.jt-row').forEach(r => r.classList.toggle('jt-no-count', open));
  summary.style.display = open ? '' : 'none';
  btn.textContent = open ? '▶' : '▼';
}
```
- **영향 범위**: `jtToggle` 호출하는 모든 JSON 트리 접기/펼치기

#### Bug 2: CLAUDE.md 칩 클릭 시 깨짐

- **변경 이유**: `hlRange()`가 `innerHTML` 직접 조작으로 DOM을 재구성하면서 HTML 엔티티(`&amp;`, `&lt;` 등) 경계에서 슬라이스가 엔티티를 잘라 깨진 HTML 생성. innerHTML 조작 대신 부모 요소에 CSS 클래스를 적용하고, 하이라이트 범위를 CSS 기반 표시로 변경.
- **Before** (JS, 라인 2681-2688):
```javascript
function hlRange(el, start, end) {
  const html = el.innerHTML;
  el.innerHTML = html.slice(0, start)
    + '<span class="mech-hl-text">' + html.slice(start, end) + '</span>'
    + html.slice(end);
  const hl = el.querySelector('.mech-hl-text');
  if (hl) requestAnimationFrame(() => hl.scrollIntoView({ behavior: 'smooth', block: 'start' }));
}
```
- **After**:
```javascript
function hlRange(el, start, end) {
  el.classList.add('mech-hl-text');
  requestAnimationFrame(() => el.scrollIntoView({ behavior: 'smooth', block: 'start' }));
}
```
- **영향 범위**: CLAUDE.md, slash command, output style 등 모든 메커니즘 하이라이트. `hlRange`는 CLAUDE.md 외 다른 메커니즘에서도 호출됨 — slash command(라인 2724+), output style(라인 2747+) 등에서도 사용. 이들은 특정 범위만 하이라이트해야 하므로 전체 요소 하이라이트는 부적절할 수 있음.

**대안: DOM Range API 사용**
innerHTML 조작 대신 text node를 찾아 Range로 감싸기:
```javascript
function hlRange(el, start, end) {
  // innerHTML에서의 위치를 text node 위치로 변환하는 건 복잡하므로,
  // 안전하게 전체 요소에 클래스 적용 (CLAUDE.md는 큰 텍스트 블록이므로 적합)
  // 다른 메커니즘은 기존 방식 유지하되 엔티티 경계 보정 추가
  const html = el.innerHTML;
  // 엔티티 경계 보정: end가 & 뒤에 있으면 ; 까지 확장
  let safeEnd = end;
  const ampIdx = html.lastIndexOf('&', safeEnd);
  if (ampIdx !== -1 && ampIdx > safeEnd - 10) {
    const semiIdx = html.indexOf(';', ampIdx);
    if (semiIdx !== -1 && semiIdx < ampIdx + 10) {
      safeEnd = semiIdx + 1;
    }
  }
  let safeStart = start;
  const ampIdx2 = html.lastIndexOf('&', safeStart);
  if (ampIdx2 !== -1 && ampIdx2 > safeStart - 10) {
    const semiIdx2 = html.indexOf(';', ampIdx2);
    if (semiIdx2 !== -1 && semiIdx2 >= safeStart) {
      safeStart = ampIdx2;
    }
  }
  el.innerHTML = html.slice(0, safeStart)
    + '<span class="mech-hl-text">' + html.slice(safeStart, safeEnd) + '</span>'
    + html.slice(safeEnd);
  const hl = el.querySelector('.mech-hl-text');
  if (hl) requestAnimationFrame(() => hl.scrollIntoView({ behavior: 'smooth', block: 'start' }));
}
```

**추천 방식**: CLAUDE.md(cm_*)에만 요소 전체 하이라이트 적용, 나머지 메커니즘은 엔티티 보정 후 기존 방식 유지.

최종 코드:
```javascript
function hlRange(el, start, end, wholeElement) {
  if (wholeElement) {
    el.classList.add('mech-hl-text');
    requestAnimationFrame(() => el.scrollIntoView({ behavior: 'smooth', block: 'start' }));
    return;
  }
  const html = el.innerHTML;
  // end 위치가 HTML 엔티티 중간이면 보정
  let safeEnd = end;
  for (let i = Math.max(0, safeEnd - 8); i < safeEnd; i++) {
    if (html[i] === '&') {
      const semi = html.indexOf(';', i);
      if (semi !== -1 && semi < i + 10 && semi >= safeEnd) {
        safeEnd = semi + 1;
        break;
      }
    }
  }
  el.innerHTML = html.slice(0, start)
    + '<span class="mech-hl-text">' + html.slice(start, safeEnd) + '</span>'
    + html.slice(safeEnd);
  const hl = el.querySelector('.mech-hl-text');
  if (hl) requestAnimationFrame(() => hl.scrollIntoView({ behavior: 'smooth', block: 'start' }));
}
```

CLAUDE.md 호출부(라인 2720):
```javascript
// Before
hlRange(el, start, end);
// After
hlRange(el, start, end, true);
```

#### 접힌 노드에 토큰 수 표시

- **변경 이유**: 접힌 노드가 `▶ [12]`만 표시. 해당 노드의 대략적인 토큰 수를 함께 보여주면 프롬프트 비용 분석에 유용.
- **Before** (JS, 라인 1703-1708):
```javascript
const typeTag = isArr ? `[${label}]` : `{${label}}`;
// ...
+ `<span class="jt-tag" id="${id}-s" onclick="jtToggle('${id}')" style="display:none">${typeTag}${trailing}</span>`
```
- **After**:
```javascript
const jsonBytes = new TextEncoder().encode(JSON.stringify(val)).length;
const tokens = Math.ceil(jsonBytes / 3.5);
const tokStr = tokens >= 1000000 ? (tokens / 1000000).toFixed(1) + 'M'
             : tokens >= 1000 ? (tokens / 1000).toFixed(1) + 'K'
             : String(tokens);
const pct = totalBytes > 0 ? (jsonBytes / totalBytes * 100) : 0;
const pctStr = pct >= 1 ? pct.toFixed(0) + '%' : pct >= 0.1 ? pct.toFixed(1) + '%' : '<0.1%';
const typeTag = isArr ? `[${label}]` : `{${label}}`;
const tokTag = `<span class="jt-tok">~${tokStr} tok · ${pctStr}</span>`;
// ...
+ `<span class="jt-tag" id="${id}-s" onclick="jtToggle('${id}')" style="display:none">${typeTag} ${tokTag}${trailing}</span>`
```

- **함수 시그니처 변경**: `buildJsonHtml(val, depth, trailing)` → `buildJsonHtml(val, depth, trailing, totalBytes)`
  - 재귀 호출에도 `totalBytes` 전달
  - `renderJsonTree`에서 최초 호출 시 `totalBytes = new TextEncoder().encode(JSON.stringify(obj)).length` 계산하여 전달

- **CSS 추가**:
```css
.jt-tok { color: var(--dim); font-size: 9px; opacity: 0.7; margin-left: 4px; }
```
- **영향 범위**: 모든 접힌 JSON 객체/배열 노드에 토큰 수 + 비중(%) 표시

#### 실제 토큰 사용량 표시

- **변경 이유**: 현재 추정치만 표시. API 응답의 `usage.input_tokens` / `output_tokens` 실제값을 보여줘야 이 요청에 토큰 얼마나 썼는지 파악 가능.
- **데이터 소스**: `entry.response.body.usage` (Claude API 응답에 포함)
  - `input_tokens`: 입력 토큰 수
  - `output_tokens`: 출력 토큰 수
  - `cache_creation_input_tokens`, `cache_read_input_tokens`: 캐시 관련 (있을 때만)
- **Before** (JS, 라인 2893-2901):
```javascript
const tokenInfo = proxyDetailTab === 'request' && data
  ? (() => {
      const bytes = new TextEncoder().encode(JSON.stringify(data)).length;
      const kb = (bytes / 1024).toFixed(1);
      const tokens = Math.ceil(bytes / 3.5);
      // ...
      return `<div class="proxy-token-pill"><span class="tt-badge">${kb} KB</span><span class="tt-badge">~${tokStr} tokens</span></div>`;
    })()
  : '';
```
- **After**: 응답이 있으면 실제 usage 표시, 없으면 추정치 유지
```javascript
const tokenInfo = proxyDetailTab === 'request' && data
  ? (() => {
      const bytes = new TextEncoder().encode(JSON.stringify(data)).length;
      const kb = (bytes / 1024).toFixed(1);
      const usage = entry.response?.body?.usage;
      if (usage) {
        const fmtTok = (n) => n >= 1000000 ? (n/1000000).toFixed(1)+'M' : n >= 1000 ? (n/1000).toFixed(1)+'K' : String(n);
        let parts = `<span class="tt-badge">${kb} KB</span>`;
        parts += `<span class="tt-badge">↑ ${fmtTok(usage.input_tokens)} in</span>`;
        parts += `<span class="tt-badge">↓ ${fmtTok(usage.output_tokens)} out</span>`;
        if (usage.cache_read_input_tokens) parts += `<span class="tt-badge">♻ ${fmtTok(usage.cache_read_input_tokens)} cache</span>`;
        parts += `<span style="color:var(--green);font-size:9px;margin-left:4px">actual</span>`;
        return `<div class="proxy-token-pill">${parts}</div>`;
      }
      // 응답 미수신 시 추정치
      const tokens = Math.ceil(bytes / 3.5);
      const tokStr = tokens >= 1000000 ? (tokens/1000000).toFixed(1)+'M' : tokens >= 1000 ? (tokens/1000).toFixed(1)+'K' : String(tokens);
      return `<div class="proxy-token-pill"><span class="tt-badge">${kb} KB</span><span class="tt-badge">~${tokStr} tokens</span><span style="color:var(--dim);font-size:9px;margin-left:4px">estimated</span></div>`;
    })()
  : '';
```
- **영향 범위**: Request 탭의 토큰 배지. 응답 수신 전엔 추정치, 수신 후엔 실제값 표시.

## 검증
- 검증 명령어: `pkill -x "Electron" 2>/dev/null; npm start &`
- 기대 결과:
  1. JSON 트리에서 노드 접으면 이후 줄 번호가 줄어듦 (접힌 줄 건너뜀)
  2. CLAUDE.md 칩 클릭 시 해당 섹션이 초록 하이라이트로 표시되며 레이아웃 깨지지 않음
  3. 접힌 노드에 `▶ [12] ~2.3K tok · 9%` 형태로 토큰 + 비중 표시
  4. 토큰 배지에 실제 `↑ 24.9K in ↓ 1.2K out ♻ 20K cache actual` 표시 (응답 전엔 `estimated`)
