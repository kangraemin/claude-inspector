# 코드 품질 이슈 9건 일괄 수정

## Context
코드 품질 리뷰에서 발견된 보안(XSS), 에러 핸들링, 입력 검증, 프로토콜 처리 이슈 9건 수정.
proxyCaptures 메모리 누수는 이미 50개 제한이 있어 false positive (수정 불필요).
포트 입력 필드는 이미 `min="1024"` 설정됨.

## 변경 파일
- `main.js` — 7건 (Issues 2,3,5,6,7,9,10)
- `public/index.html` — 2건 (Issues 1,4)

---

## Phase 1: main.js 네트워크 안전성 (Issues 2, 3, 10)

### Issue 2: EADDRINUSE 재시도 실패 시 promise 영구 대기
- **Before** (line ~197):
```javascript
server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') server.listen(0, '127.0.0.1');
  else resolve({ error: err.message });
});
```
- **After**:
```javascript
let retried = false;
server.on('error', (err) => {
  if (err.code === 'EADDRINUSE' && !retried) {
    retried = true;
    server.listen(0, '127.0.0.1');
  } else {
    resolve({ error: err.message });
  }
});
```

### Issue 3: req 스트림 에러 핸들러 누락
- **Before** (line ~138):
```javascript
const server = http.createServer((req, res) => {
  const chunks = [];
```
- **After**:
```javascript
const server = http.createServer((req, res) => {
  req.on('error', () => {
    if (!res.headersSent) res.writeHead(400);
    res.end();
  });
  const chunks = [];
```

### Issue 10: proxyRes 스트림 에러 핸들러 누락
- **Before** (line ~163):
```javascript
proxyRes.on('data', chunk => { respChunks.push(chunk); res.write(chunk); });
proxyRes.on('end', () => {
```
- **After**:
```javascript
proxyRes.on('data', chunk => { respChunks.push(chunk); res.write(chunk); });
proxyRes.on('error', () => { res.end(); });
proxyRes.on('end', () => {
```

---

## Phase 2: main.js 입력 검증 (Issues 5, 9)

### Issue 5: 토큰 추정 입력 길이 무제한
- **Before** (line ~126):
```javascript
ipcMain.handle('get-token-estimate', (_event, text) => {
  // Rough approximation: ~4 chars per token
  return Math.ceil((text || '').length / 4);
});
```
- **After**:
```javascript
ipcMain.handle('get-token-estimate', (_event, text) => {
  // Rough approximation: ~4 chars per token (cap at 10MB)
  const s = (text || '').slice(0, 10_000_000);
  return Math.ceil(s.length / 4);
});
```

### Issue 9: 특권 포트(1-1023) 허용
- **Before** (line ~132):
```javascript
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  return { error: 'Invalid port: must be 1–65535' };
}
```
- **After**:
```javascript
if (!Number.isInteger(port) || port < 1024 || port > 65535) {
  return { error: 'Invalid port: must be 1024–65535' };
}
```

---

## Phase 3: main.js 프로토콜 처리 (Issues 6, 7)

### Issue 6: SSE 파싱 — 스트림 끝에 빈 줄 없으면 마지막 이벤트 유실
이벤트 처리 로직을 헬퍼 함수로 추출하여 중복 제거.

- **Before** (line ~12-47): `var msg` 사용, for 루프 내부에서만 이벤트 처리
- **After**: `processEvent` 헬퍼 추출 + 루프 후 잔여 이벤트 처리
```javascript
function parseSseStream(text) {
  try {
    let msg = null;
    function processEvent(data) {
      try {
        const d = JSON.parse(data);
        if (d.type === 'message_start') msg = Object.assign({}, d.message, { _streaming: true });
        if (d.type === 'content_block_start' && msg) { msg.content = msg.content || []; msg.content[d.index] = Object.assign({}, d.content_block); }
        if (d.type === 'content_block_delta' && msg) { const block = msg.content && msg.content[d.index]; if (block) { if (d.delta.type === 'text_delta') block.text = (block.text || '') + d.delta.text; if (d.delta.type === 'thinking_delta') block.thinking = (block.thinking || '') + d.delta.thinking; } }
        if (d.type === 'message_delta' && msg) { if (d.delta) Object.assign(msg, d.delta); if (d.usage) msg.usage = Object.assign({}, msg.usage, d.usage); }
      } catch {}
    }
    const events = {};
    for (const rawLine of text.split('\n')) {
      const line = rawLine.replace(/\r$/, '');
      const m = line.match(/^(event|data):\s?(.*)/);
      if (m) events[m[1]] = m[2].trimEnd();
      if (line === '' && events.data) {
        processEvent(events.data);
        events.event = undefined;
        events.data = undefined;
      }
    }
    if (events.data) processEvent(events.data);
    return msg || null;
  } catch { return null; }
}
```

### Issue 7: proxy-stop race condition
- **Before** (line ~213):
```javascript
ipcMain.handle('proxy-stop', () => {
  if (!proxyServer) return { stopped: true };
  return new Promise((resolve) => {
    proxyServer.close(() => { proxyServer = null; resolve({ stopped: true }); });
  });
});
```
- **After**:
```javascript
ipcMain.handle('proxy-stop', () => {
  if (!proxyServer) return { stopped: true };
  const srv = proxyServer;
  proxyServer = null;
  return new Promise((resolve) => {
    srv.close(() => { resolve({ stopped: true }); });
  });
});
```

---

## Phase 4: public/index.html XSS 수정 (Issues 1, 4)

### Issue 1: onclick 핸들러 XSS
`safePattern` 제거, `data-key` 속성 + `esc()` 사용. `setProxyDetailMechFilter`에서 미사용 `pattern` 파라미터 제거.

- **Before** (line ~2850):
```javascript
chips.map(c => {
  const active = proxyDetailMechFilter === c.key ? ' active' : '';
  const safePattern = (c.pattern || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
  return `<span class="mech-chip ${c.cls} found btn${active}" onclick="setProxyDetailMechFilter('${c.key}','${safePattern}')">${c.label}</span>`;
}).join('')
```
- **After**:
```javascript
chips.map(c => {
  const active = proxyDetailMechFilter === c.key ? ' active' : '';
  return `<span class="mech-chip ${c.cls} found btn${active}" data-key="${escAttr(c.key)}" onclick="setProxyDetailMechFilter(this.dataset.key)">${esc(c.label)}</span>`;
}).join('')
```

함수 시그니처 변경 (line ~2770):
- **Before**: `function setProxyDetailMechFilter(key, pattern) {`
- **After**: `function setProxyDetailMechFilter(key) {`

### Issue 4: 토큰 팝오버 미이스케이프 값
`d.model`, `d.kb`, `d.total`, `d.cachePct`, `r.label`, `r.tokens`, `r.price`, `r.cost`에 `esc()` 적용.

- **rowsHtml** (line ~3441):
  - Before: `${r.label}`, `${r.tokens}`, `${r.price}`, `${r.cost}`
  - After: `${esc(r.label)}`, `${esc(r.tokens)}`, `${esc(r.price)}`, `${esc(r.cost)}`

- **popover info** (line ~3457):
  - Before: `${d.model}`, `${d.kb}`
  - After: `${esc(d.model)}`, `${esc(d.kb)}`

- **total/cachePct** (line ~3459-3460):
  - Before: `${d.total}`, `${d.cachePct}`
  - After: `${esc(d.total)}`, `${esc(d.cachePct)}`

---

## 검증
- `npm run test:unit` — 13개 단위 테스트 통과 확인
- `npm run test:e2e` — 25개 E2E 테스트 통과 확인
- 앱 실행 → 프록시 시작/중지 동작 확인
