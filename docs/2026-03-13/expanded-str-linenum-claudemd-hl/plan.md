# 펼친 문자열 wrapped line 줄 번호 표시

## 문제
긴 텍스트 줄이 컨테이너 너비를 초과하여 CSS word-break로 시각적으로 줄바꿈되면, wrapped된 부분에 줄 번호가 없어 유저 시점에서 줄 번호가 빈다.

## 해결 방식
렌더 후 컨테이너 너비를 측정하고, 그 너비에 맞게 긴 줄을 분할하여 각각 별도 `jt-exp-line` div + 줄 번호 부여. `white-space`를 `pre`로 바꿔서 CSS 자동 줄바꿈을 방지.

## 변경 파일별 상세
### `public/index.html`

#### 1. renderJsonTree에 post-render 줄 분할 함수 추가

- **변경 이유**: 빌드 시점에는 컨테이너 너비를 모르므로, 렌더 후 실제 너비를 측정하여 긴 줄을 분할해야 함.
- **Before** (JS, 라인 1778-1787):
```javascript
function renderJsonTree(container, data) {
  let obj;
  try { obj = typeof data === 'string' ? JSON.parse(data) : data; }
  catch (e) { container.textContent = typeof data === 'string' ? data : JSON.stringify(data, null, 2); return; }
  const totalBytes = new TextEncoder().encode(JSON.stringify(obj)).length;
  _jtLine = 0;
  container.innerHTML = buildJsonHtml(obj, 0, '', totalBytes)
    + `<div class="jt-line-info">${_jtLine} lines total</div>`;
  container.classList.add('jt-lined');
}
```
- **After**:
```javascript
function renderJsonTree(container, data) {
  let obj;
  try { obj = typeof data === 'string' ? JSON.parse(data) : data; }
  catch (e) { container.textContent = typeof data === 'string' ? data : JSON.stringify(data, null, 2); return; }
  const totalBytes = new TextEncoder().encode(JSON.stringify(obj)).length;
  _jtLine = 0;
  container.innerHTML = buildJsonHtml(obj, 0, '', totalBytes)
    + `<div class="jt-line-info">${_jtLine} lines total</div>`;
  container.classList.add('jt-lined');
  // 렌더 후 긴 줄 분할
  splitLongExpLines(container);
}

function splitLongExpLines(container) {
  // 컨테이너 너비 측정 → 문자 수 계산
  const measure = document.createElement('span');
  measure.style.cssText = 'visibility:hidden;position:absolute;white-space:nowrap;font:inherit;font-size:13px;font-family:monospace';
  measure.textContent = 'X'.repeat(100);
  container.appendChild(measure);
  const charWidth = measure.offsetWidth / 100;
  container.removeChild(measure);
  const availWidth = container.clientWidth - 60;
  const maxChars = Math.max(40, Math.floor(availWidth / charWidth));

  for (const block of container.querySelectorAll('.jt-str-expanded')) {
    const lines = Array.from(block.querySelectorAll('.jt-exp-line'));
    if (!lines.length) continue;
    const baseLn = parseInt(lines[0].getAttribute('data-ln')) || 1;
    let lineNum = baseLn;
    const newLines = [];
    for (const line of lines) {
      const text = line.textContent;
      if (text.length <= maxChars) {
        newLines.push({ text, ln: lineNum++, cls: line.className });
      } else {
        for (let i = 0; i < text.length; i += maxChars) {
          newLines.push({ text: text.slice(i, i + maxChars), ln: lineNum++, cls: line.className });
        }
      }
    }
    // DOM 재구성
    const toggle = block.querySelector('.jt-str-toggle');
    block.innerHTML = '';
    if (toggle) block.appendChild(toggle);
    for (const nl of newLines) {
      const div = document.createElement('div');
      div.className = nl.cls;
      div.setAttribute('data-ln', nl.ln);
      div.textContent = nl.text;
      block.appendChild(div);
    }
  }
}
```
- **영향 범위**: 모든 긴 문자열의 펼쳐진 텍스트

#### 2. jtStrToggle에서 펼칠 때도 줄 분할 호출

- **Before** (JS, 라인 1756-1766):
```javascript
function jtStrToggle(id) {
  // ... toggle logic ...
  if (btn) btn.style.display = open ? '' : 'none';
  const parentRow = body.closest('.jt-row');
  if (parentRow) parentRow.classList.toggle('jt-no-ln', !open);
}
```
- **After**:
```javascript
function jtStrToggle(id) {
  // ... toggle logic ...
  if (btn) btn.style.display = open ? '' : 'none';
  const parentRow = body.closest('.jt-row');
  if (parentRow) parentRow.classList.toggle('jt-no-ln', !open);
  // 펼칠 때 긴 줄 분할 (처음 펼칠 때만)
  if (!open && !body.dataset.split) {
    body.dataset.split = '1';
    const lined = body.closest('.jt-lined');
    if (lined) splitLongExpLines(lined, body);
  }
}
```

#### 3. CSS: jt-exp-line white-space를 pre로 변경

- **Before**:
```css
.jt-exp-line {
  display: block; white-space: pre-wrap; word-break: break-word;
  color: var(--orange); min-height: 1.3em;
}
```
- **After**:
```css
.jt-exp-line {
  display: block; white-space: pre; overflow: hidden;
  color: var(--orange); min-height: 1.3em;
}
```
- JS가 분할 처리하므로 CSS 줄바꿈은 불필요. `overflow: hidden`으로 혹시 남은 overflow 숨김.

## 검증
- 검증 명령어: `pkill -x "Electron" 2>/dev/null; npm start &`
- 기대 결과: 긴 문자열 펼침 시 모든 시각적 줄에 줄 번호 표시. wrapped line 없음.
