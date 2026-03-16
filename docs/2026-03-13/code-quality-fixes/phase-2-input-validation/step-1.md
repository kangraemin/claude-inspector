# Step 1: 토큰 추정 입력 제한 + 포트 범위 수정

## 완료 기준
- `get-token-estimate`: text를 `.slice(0, 10_000_000)`으로 제한
- `proxy-start`: 포트 검증을 `port < 1024`로 변경, 에러 메시지 "1024–65535"
- 기존 테스트 통과

## 테스트 케이스
| TC | 시나리오 | 기대 결과 | 실제 결과 |
|---|---|---|---|
| TC-1 | get-token-estimate에서 text를 10MB로 제한 | `.slice(0, 10_000_000)` 또는 동등한 코드 존재 | ✅ PASS (line 128) |
| TC-2 | 포트 검증 하한이 1024 | `port < 1024` 조건 존재 | ✅ PASS (line 133) |
| TC-3 | 포트 에러 메시지에 "1024–65535" 포함 | 에러 메시지 문자열 확인 | ✅ PASS (line 134) |
| TC-4 | npm run test:unit 통과 | 기존 13개 테스트 모두 통과 | ✅ PASS (13/13) |

## 검증 명령
- `grep -n 'slice.*10' main.js` — 입력 길이 제한 확인
- `grep -n '1024' main.js` — 포트 하한 확인
- `npm run test:unit` — 기존 테스트 통과 확인

## 실행 결과
```
$ grep -n 'slice.*10' main.js
128:  const s = (text || '').slice(0, 10_000_000);

$ grep -n '1024' main.js
133:  if (!Number.isInteger(port) || port < 1024 || port > 65535) {
134:    return { error: 'Invalid port: must be 1024–65535' };

$ npm run test:unit
✔ 13/13 tests passed (duration: 100ms)
```

## 구현 내용
- `main.js` line 128: get-token-estimate에서 text를 `.slice(0, 10_000_000)`으로 10MB 제한
- `main.js` line 133-134: 포트 하한을 1에서 1024로 변경, 에러 메시지 업데이트
