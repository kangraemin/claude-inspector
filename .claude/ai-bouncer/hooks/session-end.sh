#!/usr/bin/env bash
# SessionEnd — 이 세션이 잡고 있던 .active만 해제한다.
#
# ⚠️ 예산이 1.5초다. 여기서 다른 일을 하지 마라.
# ⚠️ 남의 lock을 지우면 그 세션이 작업 중에 잠금을 잃는다. 절대 glob 삭제 금지.
#
# 작업 자체는 state.json에 남으므로, lock 해제로 잃는 것은 없다.

set -uo pipefail

INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

SESSION="$(printf '%s' "$INPUT" | jq -r '.session_id // empty')"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty')"
[ -n "$SESSION" ] || exit 0
[ -n "$CWD" ] || CWD="$PWD"

TASKS="$CWD/.ai-bouncer/tasks"
[ -d "$TASKS" ] || exit 0

for active in "$TASKS"/*/.active; do
  [ -f "$active" ] || continue
  owner="$(jq -r '.session_id // empty' "$active" 2>/dev/null)"
  # 내 것일 때만. 불일치·파싱실패는 남의 것으로 간주하고 건드리지 않는다.
  [ -n "$owner" ] && [ "$owner" = "$SESSION" ] || continue
  rm -f "$active"
done
exit 0
