# Claude Inspector

## UI 버그 수정 원칙

1. **진단 먼저, 수정은 한 번에**: 부모→자식 전체 CSS/스타일 체인을 분석하고 원인을 특정한 후 수정한다. 추측으로 속성 하나 넣어보고 안 되면 또 넣어보는 식 금지.
2. **확인 후 커밋**: 앱 재시작 → 사용자 확인 → 커밋. "fix" 커밋이 실제로 안 고쳐진 상태로 푸시되면 안 된다.
3. **단순한 해법 우선**: 사용자가 단순한 방향을 제시하면 그대로 한다. flex 트릭보다 `display:block + overflow-y:auto`가 나을 수 있다.

## proxyDetailView 구조

- `#proxyDetailView`는 inline style로 `flex:1;overflow:hidden;display:flex;flex-direction:column` 지정됨
- **Messages 탭**: `container.style.cssText`로 `display:block;overflow-y:auto`로 전체 전환 (부분 override 불가)
- **다른 탭 전환 시**: `cssText`로 원래 flex 스타일 복원

<!-- ai-bouncer:start -->
## ai-bouncer

코드 수정·기능 구현·버그 수정·리팩터링 등 **개발 작업은 `/dev-bounce`로 시작한다.**
스킬을 거치지 않고 Edit / Write / Bash로 소스를 고치지 않는다.

- 작업이 시작되면 hook이 단계별 규칙을 강제한다. 시작 전에는 아무것도 막지 않는다.
- 진행 중인 작업이 있는지 `bouncer status`로 먼저 확인하고, 있으면 이어서 한다.
- 질문·설명 요청은 해당 없다. 그냥 답하면 된다.
- hook이 차단하면 우회하지 말고 차단 사유에 적힌 조건을 충족시켜라.
<!-- ai-bouncer:end -->
