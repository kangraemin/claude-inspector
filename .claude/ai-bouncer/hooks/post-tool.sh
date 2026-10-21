#!/usr/bin/env bash
# PostToolUse — 모델이 위조할 수 없는 증거를 기록한다.
#
# 기록 대상 둘:
#   ExitPlanMode 성공  → blocking: plan_approved 충족
#   Skill 성공         → blocking: skill:<이름> 충족
# (실패하면 PostToolUse가 아예 안 뜨므로, 여기 도달했다는 것 자체가 성공 증거다.)
#
# 그리고 읽기 전용 단계의 Bash(성공·실패 모두): 작업 트리가 단계 진입 때와 달라졌으면 알린다.

set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../engine/lib/common.sh"

INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

TOOL="$(jq -r '.tool_name // empty' <<<"$INPUT")"
case "$TOOL" in ExitPlanMode|Skill|Bash) ;; *) exit 0 ;; esac

SESSION="$(jq -r '.session_id // empty' <<<"$INPUT")"
CWD="$(jq -r '.cwd // empty'            <<<"$INPUT")"
[ -n "$CWD" ] || CWD="$PWD"
[ -n "$SESSION" ] || exit 0

TASK="$(bouncer_my_task "$CWD" "$SESSION")" || exit 0
STAGE="$(bouncer_state "$TASK" '.current_stage')"
[ -n "$STAGE" ] || exit 0

if [ "$TOOL" = "Bash" ]; then
  # 읽기 전용(`edit_files: true`)은 **작업 트리 수정**만 막는다. 도구 설치·캐시·/tmp 쓰기,
  # npm/npx/테스트 실행은 명령 이름으로 미리 막지 않고, 실행 뒤 트리가 바뀌었는지로 본다.
  [ "$(bouncer_stage "$CWD" "$STAGE" | jq -r '.forbid.edit_files // null')" = "true" ] || exit 0
  CH="$(bouncer_ro_changes "$TASK" "$STAGE")"
  [ -n "$CH" ] || exit 0
  bouncer_block "⛔ [ai-bouncer / $STAGE] 방금 명령이 프로젝트 작업 트리를 바꿨다:
$(printf '%s\n' "$CH" | head -20 | sed 's/^/    /')

이 단계에서는 프로젝트 코드를 고칠 수 없다. 지금 바로 되돌려라:
    bouncer restore
(되돌리기 전 내용은 git 객체로 남는다. 수정이 필요하면 구현 단계로 돌아가서 한다.)"
fi

if [ "$TOOL" = "ExitPlanMode" ]; then
  WANT="plan_approved"
  # 승인된 계획을 그대로 체크리스트로 옮긴다. 계획을 세워 승인까지 받아놓고
  # 구현 단계에서 목록을 다시 적게 하면 그 사이에서 항목이 샌다.
  # 이미 목록이 있으면 건드리지 않는다 (사용자가 손본 것을 덮지 않는다).
  if [ "$(jq -r '(.checklist // []) | length' "$TASK/state.json" 2>/dev/null)" = 0 ] \
     && command -v python3 >/dev/null 2>&1; then
    ITEMS="$(jq -r '.tool_input.plan // empty' <<<"$INPUT" | python3 -c '
import json, re, sys
plan = sys.stdin.read()
items, seen, fence = [], set(), False
for line in plan.split("\n"):
    t = line.strip()
    if t.startswith("```") or t.startswith("~~~"):
        fence = not fence          # 코드블록 안은 계획 항목이 아니다
        continue
    if fence:
        continue
    m = re.match(r"^(?:[-*+]|\d+[.)])\s+(.+)$", t)
    if not m:
        continue
    text = m.group(1)
    text = re.sub(r"^\[[ xX]\]\s*", "", text)      # 체크박스 표기 제거
    text = re.sub(r"`([^`]*)`", r"\1", text)        # 인라인 코드는 내용만
    text = re.sub(r"\*\*([^*]*)\*\*", r"\1", text)  # 굵게만 벗긴다
    text = text.strip()
    if len(text) < 3 or text in seen:
        continue
    seen.add(text)
    items.append(text[:200])
print(json.dumps(items[:40], ensure_ascii=False))
' 2>/dev/null)"
    if [ -n "$ITEMS" ] && [ "$ITEMS" != "[]" ]; then
      UT="$(jq -r '.user_turns // 0' "$TASK/state.json" 2>/dev/null)"
      [ "$UT" -eq "$UT" ] 2>/dev/null || UT=0
      bouncer_state_update "$TASK" --argjson items "$ITEMS" --argjson u "$UT" \
        --arg plan "$(jq -r '.tool_input.plan // empty' <<<"$INPUT")" \
        '.plan = $plan
         | .checklist = ($items | map({text: ., done: false}))
         | .checklist_turn = $u' 2>/dev/null || true
    fi
  fi
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
