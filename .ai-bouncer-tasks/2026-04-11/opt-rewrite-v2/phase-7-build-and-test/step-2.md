# Step 2: 빌드 검증

## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-01 | npm run build:vite — Vite 빌드 성공 | dist/renderer/index.html 생성 | ✅ |
| TC-02 | npx tsc --noEmit — TypeScript 타입 에러 없음 | 에러 0개 | ✅ |

검증 명령어:
```bash
npm run build:vite 2>&1 | tail -10
npx tsc --noEmit 2>&1 | tail -5
ls dist/renderer/
```

## 실행출력

TC-01: npx vite build 2>&1 | tail -20
→ vite v8.0.8 building client environment for production...
→ ✓ 57 modules transformed.
→ dist/renderer/index.html  0.40 kB │ gzip: 0.27 kB
→ dist/renderer/assets/index-DK93p2WO.css  10.80 kB │ gzip: 2.60 kB
→ dist/renderer/assets/index-DIOgW7Ev.js  230.77 kB │ gzip: 73.21 kB
→ ✓ built in 339ms

TC-02: npx tsc --noEmit 2>&1 | tail -10
→ (출력 없음 — 에러 0개)

TC-01/02: ls dist/renderer/
→ assets  index.html
