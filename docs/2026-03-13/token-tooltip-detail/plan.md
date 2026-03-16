# 토큰 tooltip 계산 과정 표시

## 변경 파일별 상세
### `public/index.html`

- **변경 이유**: hover tooltip에 단순 요약만 있어서 비용이 어떻게 계산됐는지 모름. 각 토큰 종류별 단가 × 수량 = 소계를 보여줘야 함.
- **Before** (JS, 라인 3045):
```javascript
const tooltip = `입력: ${fmtTok(totalIn)} 토큰 (캐시읽기 ${fmtTok(cacheRead)} + 캐시쓰기 ${fmtTok(cacheWrite)} + 미캐시 ${fmtTok(uncached)})\n출력: ${fmtTok(outTok)} 토큰\n캐시 적중률: ${cachePct}%\n추정 비용: ${costStr}`;
```
- **After**:
```javascript
const fmtCost = (n) => '$' + (n / 1_000_000).toFixed(4);
const tooltip = [
  `[비용 계산] 모델: ${model || '불명'}`,
  ``,
  `캐시읽기: ${fmtTok(cacheRead)} × $${crP}/MTok = ${fmtCost(cacheRead * crP)}`,
  `캐시쓰기: ${fmtTok(cacheWrite)} × $${cwP}/MTok = ${fmtCost(cacheWrite * cwP)}`,
  `미캐시 입력: ${fmtTok(uncached)} × $${inP}/MTok = ${fmtCost(uncached * inP)}`,
  `출력: ${fmtTok(outTok)} × $${outP}/MTok = ${fmtCost(outTok * outP)}`,
  ``,
  `합계: ${costStr}`,
  `캐시 적중률: ${cachePct}%`
].join('\n');
```
- **영향 범위**: tooltip만 변경, 배지 표시는 그대로

## 검증
- `pkill -x "Electron" 2>/dev/null; npm start &`
- hover 시 계산 과정 표시 확인
