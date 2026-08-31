#!/usr/bin/env bash
# PostToolUse — 모델이 위조할 수 없는 증거를 기록한다.
#
# 기록 대상 둘뿐:
#   ExitPlanMode 성공  → blocking: plan_approved 충족
#   Skill 성공         → blocking: skill:<이름> 충족
# (실패하면 PostToolUse가 아예 안 뜨므로, 여기 도달했다는 것 자체가 성공 증거다.)

set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../engine/lib/common.sh"

INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

TOOL="$(jq -r '.tool_name // empty' <<<"$INPUT")"
case "$TOOL" in ExitPlanMode|Skill) ;; *) exit 0 ;; esac

SESSION="$(jq -r '.session_id // empty' <<<"$INPUT")"
CWD="$(jq -r '.cwd // empty'            <<<"$INPUT")"
[ -n "$CWD" ] || CWD="$PWD"
[ -n "$SESSION" ] || exit 0

TASK="$(bouncer_my_task "$CWD" "$SESSION")" || exit 0
STAGE="$(bouncer_state "$TASK" '.current_stage')"
[ -n "$STAGE" ] || exit 0

if [ "$TOOL" = "ExitPlanMode" ]; then
  WANT="plan_approved"
else
  SKILL="$(jq -r '.tool_input.skill // .tool_input.name // empty' <<<"$INPUT")"
  [ -n "$SKILL" ] || exit 0
  WANT="skill:$SKILL"
fi

# 현재 스테이지에서 이 증거를 기다리는 step에만 기록한다.
while IFS= read -r id; do
  [ -z "$id" ] && continue
  bouncer_state_update "$TASK" --arg k "$id" '.evidence[$k] = true'
done < <(bouncer_stage "$CWD" "$STAGE" | jq -r --arg w "$WANT" '.steps[]? | select(.blocking == $w) | .id')
exit 0
