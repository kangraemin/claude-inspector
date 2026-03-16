# Step 1: 시뮬레이터 전용 JS 함수/변수/i18n 키 제거

## TC

| # | 테스트 | 기대결과 | 실제결과 |
|---|--------|----------|----------|
| TC-1 | SHOW_SIMULATOR 상수 없음 | grep 결과 없음 | ✅ |
| TC-2 | getMechanisms 함수 없음 | grep 결과 없음 | ✅ |
| TC-3 | buildPayload/buildSendablePayload 함수 없음 | grep 결과 없음 | ✅ |
| TC-4 | sendToApi/simulateSkill/simulateSubAgent 함수 없음 | grep 결과 없음 | ✅ |
| TC-5 | landing/history/mech i18n 키 없음 | grep 결과 없음 | ✅ |
| TC-6 | proxy/messages/analysis/token/onboard i18n 키 유지 | grep 13건 | ✅ |
| TC-7 | esc/escAttr/renderJsonTree 유틸 유지 | grep 3건 | ✅ |
| TC-8 | applyI18n 함수 유지, renderHistory 호출 없음 | applyI18n 1건, renderHistory 0건 | ✅ |
| TC-9 | init 코드에서 switchM/savedKey 제거 | JS 코드에서 참조 없음 | ✅ |
| TC-10 | JS 문법 오류 없음 | node --check 통과 | ✅ |

## 구현 내용
- LOCALES에서 시뮬레이터 전용 i18n 키 제거: landing, history, mech, export, form, api, apiInput, header의 simulator 전용 키
- copy 키는 proxy에서도 사용하므로 최소 세트(copy, copied)만 유지
- getMechanisms, SHOW_SIMULATOR, 시뮬레이터 상태 변수(current, lastResponseText, currentPayload, mdEnabled, exportLang, sessionHistory) 제거
- buildPayload, buildSendablePayload, collectCfg 제거
- updatePreview, renderForm, switchM, showPTab, copyPayload, callApi, sendToApi, simulateSkill, simulateSubAgent, copyResponse, renderResponseContent, toggleMd, 모든 Export 함수, 모든 History 함수, openFilePicker, onApiKeyChange 제거
- applyI18n()에서 renderHistory, normalPanels form re-render 코드 제거
- Init 코드: modelSel change listener, savedKey 복원, SHOW_SIMULATOR 분기 모두 제거. 프록시 패널 직접 표시로 전환
- 3578줄 → 2626줄 (952줄 제거)

## 실행 결과

```
$ grep -c "SHOW_SIMULATOR" public/index.html
0

$ grep -c "getMechanisms" public/index.html
0

$ grep -c "buildPayload|buildSendablePayload" public/index.html
0

$ grep -c "function sendToApi|function simulateSkill|function simulateSubAgent" public/index.html
0

$ grep -c "proxy:|messages:|analysis:|token:|onboard:" public/index.html
13

$ node --check /tmp/test-js.js
SYNTAX:OK
```
