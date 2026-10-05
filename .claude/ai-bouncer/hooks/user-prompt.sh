#!/usr/bin/env bash
# UserPromptSubmit — 사용자가 실제로 입력했다는 사실만 기록한다.
#
# `inject` + `blocking: true` 는 "사람이 실제로 답해야 통과"를 뜻한다.
# 그걸 확인할 수단이 이 hook뿐이다. 이게 없으면 모델이 같은 턴에
# `bouncer done` 을 쳐서 통과할 수 있고, 그러면 게이트가 자기 보고가 된다.
#
# 프롬프트 내용은 저장하지 않는다. 턴이 발생했다는 카운터만 올린다.
#
# 단, UserPromptSubmit 은 사람 입력에만 불리지 않는다. 백그라운드 작업 완료 알림
# (<task-notification>)과 시스템 리마인더도 이 이벤트로 들어온다. 그걸 사람 턴으로
# 세면 모델이 백그라운드 작업 하나 띄우고 기다리는 것만으로 "사람 확인" 게이트가
# 열린다 — 실사용에서 실제로 그렇게 통과됐다. 사람 입력이 아닌 것은 세지 않는다.

set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../engine/lib/common.sh"

INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

# 판정은 내용 표식 + (있으면) 출처 필드. 출처 필드가 없는 구버전 입력은 표식만 본다.
HUMAN="$(jq -r '
  (.prompt // "") as $p
  | if ($p | type) != "string" then "no"
    elif ($p | contains("<task-notification>")) then "no"
    elif ($p | ltrimstr(" ") | startswith("<system-reminder>")) then "no"
    elif has("origin") and ((.origin | type) != "object" or .origin.kind != "human") then "no"
    elif has("turnOrigin") and .turnOrigin != "human" then "no"
    else "yes" end' <<<"$INPUT" 2>/dev/null)"
[ "$HUMAN" = "yes" ] || exit 0

SESSION="$(jq -r '.session_id // empty' <<<"$INPUT")"
CWD="$(jq -r '.cwd // empty' <<<"$INPUT")"
[ -n "$CWD" ] || CWD="$PWD"
[ -n "$SESSION" ] || exit 0

TASK="$(bouncer_my_task "$CWD" "$SESSION")" || exit 0
bouncer_state_update "$TASK" '.user_turns = ((.user_turns // 0) + 1)'
exit 0
