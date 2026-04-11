## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-1 | logo-ver span 렌더링 코드 존재 | `grep -c 'logo-ver' src/presentation/components/Header/Header.tsx` → 1 | ✅ |
| TC-2 | build-info.json fetch 코드 존재 | `grep -c 'build-info.json' src/presentation/components/Header/Header.tsx` → 1 | ✅ |

## 실행 출력

TC-1: 1, TC-2: 1 — 통과
