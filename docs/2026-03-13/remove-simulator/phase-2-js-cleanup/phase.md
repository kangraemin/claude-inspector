# Phase 2: index.html JS cleanup

## 목표
index.html에서 시뮬레이터 전용 JS 코드(함수, 변수, i18n 키)를 제거하고 프록시 모드 직접 표시로 전환한다.

## 범위
- LOCALES에서 시뮬레이터 전용 i18n 키 제거 (landing, history, mech, export, form, api, apiInput)
- 시뮬레이터 전용 함수 제거 (getMechanisms, buildPayload, buildSendablePayload, collectCfg, updatePreview, renderForm, switchM, showPTab, copyPayload, callApi, sendToApi, simulateSkill, simulateSubAgent, copyResponse, renderResponseContent, toggleMd, generateCurl, generatePython, generateTypeScript, updateExport, showExportLang, copyExport, saveHistory, renderHistory, restoreHistory, toggleHistory, openFilePicker, onApiKeyChange, mechBadge, BADGE_STYLES)
- 시뮬레이터 전용 상태 변수 제거 (current, lastResponseText, currentPayload, mdEnabled, exportLang, sessionHistory, SHOW_SIMULATOR)
- applyI18n()에서 시뮬레이터 re-render 코드 제거
- Init 코드에서 시뮬레이터 관련 로직 제거, 프록시 직접 표시

## Steps
- Step 1: 시뮬레이터 전용 JS 함수/변수/i18n 키 제거 및 applyI18n/init 수정
