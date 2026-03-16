# Step 1: 시뮬레이터 IPC 핸들러 + SDK 제거

## TC

| # | 테스트 | 기대결과 | 실제결과 |
|---|--------|----------|----------|
| 1 | main.js에 Anthropic SDK import 없음 | grep 결과 없음 | ✅ |
| 2 | main.js에 send-to-claude/open-file/get-token-estimate 핸들러 없음 | grep 결과 없음 | ✅ |
| 3 | main.js에 fs/dialog import 없음 | grep 결과 없음 | ✅ |
| 4 | preload.js에 sendToClaude/openFile/estimateTokens 없음 | grep 결과 없음 | ✅ |
| 5 | package.json에 @anthropic-ai/sdk 없음 | grep 결과 없음 | ✅ |
| 6 | proxy 핸들러 유지 (proxy-start/stop/status) | 3개 모두 존재 | ✅ |
| 7 | main.js 문법 검사 통과 | SYNTAX:OK | ✅ |
| 8 | preload.js 문법 검사 통과 | SYNTAX:OK | ✅ |
| 9 | package.json JSON 유효 | JSON:OK | ✅ |

## 구현 내용
- main.js: `const { Anthropic } = require('@anthropic-ai/sdk')` 제거, `fs`/`dialog` import 제거, send-to-claude/open-file/get-token-estimate IPC 핸들러 3개 제거 (245줄 → 210줄)
- preload.js: sendToClaude, openFile, estimateTokens API 3개 제거 (21줄 → 17줄)
- package.json: @anthropic-ai/sdk 의존성 제거, build.files에서 SDK 경로 제거

## 실행 결과

```
$ grep -n "anthropic-ai\|send-to-claude\|open-file\|get-token-estimate\|dialog\|require('fs')" main.js
(no output — all simulator code removed)

$ grep -n "sendToClaude\|openFile\|estimateTokens" preload.js
(no output — all simulator APIs removed)

$ grep -n "anthropic-ai" package.json
(no output — SDK dependency removed)

$ grep -c "proxy-start\|proxy-stop\|proxy-status" main.js
3 (all proxy handlers preserved)

$ node -c main.js
SYNTAX:OK

$ node -c preload.js
SYNTAX:OK

$ node -e "JSON.parse(require('fs').readFileSync('package.json','utf8')); console.log('JSON:OK')"
JSON:OK
```
