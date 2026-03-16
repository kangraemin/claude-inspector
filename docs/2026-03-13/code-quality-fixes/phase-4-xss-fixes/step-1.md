# Step 1: mech-chip onclick XSS 수정

## 완료 기준
- `safePattern` 변수 및 관련 코드 제거
- `data-key="${escAttr(c.key)}"` 속성 사용
- onclick에서 `this.dataset.key`로 접근
- `setProxyDetailMechFilter(key)` 파라미터 1개로 변경
- 기존 테스트 통과

## 테스트 케이스
| TC | 시나리오 | 기대 결과 | 실제 결과 |
|---|---|---|---|
| TC-1 | safePattern 변수 제거 | `safePattern` 문자열이 index.html에 없음 | ✅ PASS (count=0) |
| TC-2 | data-key 속성 사용 | `data-key=` 문자열이 mech-chip에 존재 | ✅ PASS (line 2852) |
| TC-3 | onclick에서 this.dataset.key 사용 | `this.dataset.key` 패턴 존재 | ✅ PASS (line 2852) |
| TC-4 | setProxyDetailMechFilter 파라미터 1개 | `function setProxyDetailMechFilter(key)` 시그니처 확인 | ✅ PASS (line 2770) |
| TC-5 | escAttr 함수로 key 이스케이프 | `escAttr(c.key)` 호출 확인 | ✅ PASS (line 2852) |
| TC-6 | npm run test:unit 통과 | 기존 13개 테스트 모두 통과 | ✅ PASS (13/13) |

## 검증 명령
- `grep -c 'safePattern' public/index.html` — 0이어야 함 (제거 확인)
- `grep 'data-key' public/index.html` — data-key 사용 확인
- `grep 'this.dataset.key' public/index.html` — dataset 접근 확인
- `grep 'setProxyDetailMechFilter(key)' public/index.html` — 시그니처 확인
- `npm run test:unit` — 기존 테스트 통과 확인

## 실행 결과
```
$ grep -c 'safePattern' public/index.html
0

$ grep -n 'data-key\|this.dataset.key\|setProxyDetailMechFilter(key)' public/index.html
2770:function setProxyDetailMechFilter(key) {
2852:        return `<span ... data-key="${escAttr(c.key)}" onclick="setProxyDetailMechFilter(this.dataset.key)">${esc(c.label)}</span>`;

$ npm run test:unit
✔ 13/13 tests passed (duration: 103ms)
```

## 구현 내용
- `public/index.html` line 2770: `setProxyDetailMechFilter(key, pattern)` → `setProxyDetailMechFilter(key)` 시그니처 변경
- `public/index.html` line 2852: safePattern 제거, `data-key="${escAttr(c.key)}"` + `this.dataset.key` + `esc(c.label)` 적용
