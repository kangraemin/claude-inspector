# Step 4: CSS + App 통합

## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-01 | src/styles/index.css — 기존 index.html CSS 이관 | 파일 존재 | ✅ |
| TC-02 | App.tsx — Header + ProxyPanel + AiFlowPanel 레이아웃 | 파일 업데이트됨 | ✅ |
| TC-03 | npx tsc --noEmit 에러 없음 | exit 0 | ✅ |
| TC-04 | vite build 에러 없음 | exit 0 | ✅ |

검증 명령어:
```bash
ls src/styles/
npx tsc --noEmit && echo "tsc OK"
npx vite build 2>&1 | tail -5
```

## 실행출력

```
$ ls src/styles/
index.css

$ npx tsc --noEmit && echo "tsc OK"
tsc OK

$ npx vite build 2>&1 | tail -8
transforming...✓ 57 modules transformed.
rendering chunks...
computing gzip size...
dist/renderer/index.html                   0.40 kB │ gzip:  0.27 kB
dist/renderer/assets/index-DK93p2WO.css   10.80 kB │ gzip:  2.60 kB
dist/renderer/assets/index-DIOgW7Ev.js   230.77 kB │ gzip: 73.21 kB

✓ built in 543ms
```

TC-01 ✅ src/styles/index.css — 기존 index.html CSS 이관
TC-02 ✅ App.tsx — Header + ProxyPanel + AiFlowPanel 레이아웃
TC-03 ✅ tsc --noEmit → exit 0
TC-04 ✅ vite build → 성공 (57 modules, 543ms)
