# 토큰 배지 UX 개선

## 문제
현재 `↑ 23.8K in ↓ 6 out ♻23.7K read · 📝21 write · 3 uncached actual` 표시가 의미를 알기 어려움.

## 해결
직관적인 2줄 표시:
- 1줄: `입력 23.8K tok · 출력 6 tok · ~$0.02`
- 2줄: `캐시 99% (23.7K read + 21 write) · 미캐시 3`

hover 시 상세 설명 tooltip.

## 변경 파일별 상세
### `public/index.html`

#### 토큰 배지 표시 변경

- **변경 이유**: 현재 기호(↑↓♻📝)와 영어 약어가 혼재해서 의미 파악 어려움. 한글 레이블 + 비용 추정 + 캐시 비율로 직관화.
- **Before** (JS, 라인 3026-3048):
```javascript
const usage = entry.response?.body?.usage;
if (usage) {
  const totalIn = (usage.input_tokens || 0) + (usage.cache_read_input_tokens || 0) + (usage.cache_creation_input_tokens || 0);
  let parts = `<span class="tt-badge">${kb} KB</span>`;
  parts += `<span class="tt-badge">↑ ${fmtTok(totalIn)} in</span>`;
  parts += `<span class="tt-badge">↓ ${fmtTok(usage.output_tokens)} out</span>`;
  const cacheRead = usage.cache_read_input_tokens || 0;
  const cacheWrite = usage.cache_creation_input_tokens || 0;
  if (cacheRead || cacheWrite) {
    const cacheParts = [];
    if (cacheRead) cacheParts.push(`♻${fmtTok(cacheRead)} read`);
    if (cacheWrite) cacheParts.push(`📝${fmtTok(cacheWrite)} write`);
    const uncached = usage.input_tokens || 0;
    if (uncached) cacheParts.push(`${fmtTok(uncached)} uncached`);
    parts += `<span class="tt-badge" style="opacity:0.7">${cacheParts.join(' · ')}</span>`;
  }
  parts += `<span style="color:var(--green);font-size:9px;margin-left:4px">actual</span>`;
  return `<div class="proxy-token-pill">${parts}</div>`;
}
const tokens = Math.ceil(bytes / 3.5);
const tokStr = fmtTok(tokens);
return `<div class="proxy-token-pill"><span class="tt-badge">${kb} KB</span><span class="tt-badge">~${tokStr} tokens</span><span style="color:var(--dim);font-size:9px;margin-left:4px">estimated</span></div>`;
```
- **After**:
```javascript
const usage = entry.response?.body?.usage;
if (usage) {
  const totalIn = (usage.input_tokens || 0) + (usage.cache_read_input_tokens || 0) + (usage.cache_creation_input_tokens || 0);
  const outTok = usage.output_tokens || 0;
  const cacheRead = usage.cache_read_input_tokens || 0;
  const cacheWrite = usage.cache_creation_input_tokens || 0;
  const uncached = usage.input_tokens || 0;

  // 비용 추정 (모델별)
  const model = entry.request?.body?.model || entry.response?.body?.model || '';
  const isOpus = model.includes('opus');
  const inPrice = isOpus ? 15 : 3; // $/MTok
  const outPrice = isOpus ? 75 : 15;
  const cacheReadPrice = isOpus ? 1.5 : 0.3;
  const cacheWritePrice = isOpus ? 18.75 : 3.75;
  const cost = (uncached * inPrice + cacheRead * cacheReadPrice + cacheWrite * cacheWritePrice + outTok * outPrice) / 1_000_000;
  const costStr = cost >= 1 ? '$' + cost.toFixed(2) : cost >= 0.01 ? '$' + cost.toFixed(3) : '<$0.01';

  // 캐시 비율
  const cachePct = totalIn > 0 ? Math.round((cacheRead / totalIn) * 100) : 0;

  let html = `<div class="proxy-token-pill" title="입력: ${fmtTok(totalIn)} (캐시읽기 ${fmtTok(cacheRead)} + 캐시쓰기 ${fmtTok(cacheWrite)} + 미캐시 ${fmtTok(uncached)})\n출력: ${fmtTok(outTok)}\n비용: ${costStr}">`;
  html += `<span class="tt-badge">${kb} KB</span>`;
  html += `<span class="tt-badge">입력 ${fmtTok(totalIn)}</span>`;
  html += `<span class="tt-badge">출력 ${fmtTok(outTok)}</span>`;
  if (cachePct > 0) html += `<span class="tt-badge" style="color:var(--green)">캐시 ${cachePct}%</span>`;
  html += `<span class="tt-badge" style="color:var(--yellow)">${costStr}</span>`;
  html += `</div>`;
  return html;
}
const tokens = Math.ceil(bytes / 3.5);
const tokStr = fmtTok(tokens);
return `<div class="proxy-token-pill"><span class="tt-badge">${kb} KB</span><span class="tt-badge">~${tokStr} tokens (추정)</span></div>`;
```
- **영향 범위**: Request 탭 토큰 배지만 변경

## 검증
- 검증 명령어: `pkill -x "Electron" 2>/dev/null; npm start &`
- 기대 결과: 토큰 배지에 `입력 23.8K · 출력 6 · 캐시 99% · $0.02` 형태 표시. hover 시 상세 tooltip.
