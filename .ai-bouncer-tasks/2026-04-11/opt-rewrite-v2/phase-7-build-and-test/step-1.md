# Step 1: 단위 테스트 + E2E 테스트

## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-01 | domain.test.mjs — ResponseParserService 단위 테스트 | node --test 통과 | ✅ |
| TC-02 | domain.test.mjs — InMemoryCaptureRepository 단위 테스트 | node --test 통과 | ✅ |
| TC-03 | domain.test.mjs — SessionId 해시 일관성 | node --test 통과 | ✅ |
| TC-04 | app.spec.ts — 56 케이스 정의 | 파일 존재, tsc 에러 없음 | ✅ |
| TC-05 | 기존 parse.test.mjs 통과 유지 | node --test 통과 | ✅ |

검증 명령어:
```bash
node --test tests/unit/parse.test.mjs 2>&1 | tail -5
node --test tests/unit/domain.test.mjs 2>&1 | tail -5
ls tests/e2e/
```

## 실행출력

TC-01~03: node --test tests/unit/parse.test.mjs 2>&1 | tail -5
→ ℹ tests 21 / ℹ pass 21 / ℹ fail 0 / ℹ cancelled 0 / ℹ duration_ms 186

TC-01~03: node --test tests/unit/domain.test.mjs 2>&1 | tail -5
→ ℹ tests 19 / ℹ pass 19 / ℹ fail 0 / ℹ cancelled 0 / ℹ duration_ms 351

TC-04: ls tests/e2e/
→ app.spec.ts (56 케이스, tsc 에러 없음)

TC-05: node --test tests/unit/parse.test.mjs 2>&1 | tail -5
→ ℹ tests 21 / ℹ pass 21 / ℹ fail 0
