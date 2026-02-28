# Handoff: Messages 탭 스크롤 수정

## 목표
- Proxy → Messages 탭에서 메시지 카드가 정상 스크롤되도록

## 완료된 것
- ✅ `proxyDetailView`를 `cssText`로 `display:block;overflow-y:auto` 전환
- ✅ "내가 보낸 것" 필터에서 typed text 없는 메시지 스킵
- ✅ user 필터에서 tool_use/tool_result 블록 숨김

## 시도했지만 실패한 것
- ❌ `min-height:0` 추가: flex container의 overflow:hidden과 충돌
- ❌ `container.style.overflow = 'auto'`: inline style 부분 override로는 display:flex가 남아서 스크롤 안 됨

## 다음 단계
1. 사용자에게 Messages 탭 스크롤 정상 동작 확인받기
2. 확인 안 되면 DevTools로 실제 computed style 확인 필요
