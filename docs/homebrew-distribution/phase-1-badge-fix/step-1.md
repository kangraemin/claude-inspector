# Phase 1 Step 1: Fix mechanism badge click bug

## 변경 대상
- `public/index.html`: `highlightMechInJsonTree` 함수

## TC

| TC | 설명 | 예상 결과 | 실제 결과 |
|----|------|-----------|-----------|
| TC-1 | querySelectorAll 셀렉터가 `.jt-str, .jt-str-expanded`를 포함 | 3곳 모두 변경 | ✅ 3곳 변경 완료 |
| TC-2 | expandLongStr 헬퍼 함수 추가 | 함수 존재 | ✅ highlightMechInJsonTree 내부에 추가 |
| TC-3 | CLAUDE.md 섹션에서 expandLongStr + expandAncestors 호출 | hlRange 전 호출 | ✅ hlRange 전에 호출 |
| TC-4 | slash command 섹션에서 expandLongStr 호출 | expandAncestors 전 호출 | ✅ expandAncestors 전에 호출 |
