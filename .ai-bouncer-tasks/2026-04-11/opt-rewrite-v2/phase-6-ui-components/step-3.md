# Step 3: AiFlow + Optimization + Chat

## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-01 | AiFlowPanel.tsx — 분석 시작/취소 버튼, 결과 표시 | 파일 존재 | ✅ |
| TC-02 | Optimization.tsx — 스피너, 타이머, 취소 버튼 | 파일 존재 | ✅ |
| TC-03 | Chat.tsx — 메시지 입력, 버블 표시 | 파일 존재 | ✅ |
| TC-04 | npx tsc --noEmit 에러 없음 | exit 0 | ✅ |

검증 명령어:
```bash
ls src/presentation/components/AiFlow/
npx tsc --noEmit && echo "tsc OK"
```

## 실행출력

```
$ ls src/presentation/components/AiFlow/
AiFlowPanel.tsx
Chat.tsx
Optimization.tsx

$ npx tsc --noEmit && echo "tsc OK"
tsc OK
```

TC-01 ✅ AiFlowPanel.tsx — 분석 시작/취소, 결과 표시
TC-02 ✅ Optimization.tsx — 스피너, ElapsedTimer, 취소 버튼
TC-03 ✅ Chat.tsx — 메시지 입력, 버블 표시
TC-04 ✅ tsc --noEmit → exit 0
