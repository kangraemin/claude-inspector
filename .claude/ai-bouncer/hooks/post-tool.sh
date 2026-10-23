#!/usr/bin/env bash
# PostToolUse — ExitPlanMode 가 승인되면 그 계획을 체크리스트로 옮긴다.
# (실패하면 PostToolUse가 아예 안 뜨므로, 여기 도달했다는 것 자체가 승인 증거다.)
#
# 계획 승인 게이트(blocking: plan_approved)·skill 증거·읽기 전용 단계 트리 감시는 지웠다 —
# 앞의 둘은 Claude Code plan 모드가, 뒤는 증거 무효화(코드 지문)가 맡는다.

set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../engine/lib/common.sh"

INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

{ IFS= read -r TOOL; IFS= read -r SESSION; IFS= read -r CWD; } \
  < <(jq -r '(.tool_name // "" | tostring), (.session_id // "" | tostring), (.cwd // "" | tostring)' <<<"$INPUT" 2>/dev/null)
[ "$TOOL" = "ExitPlanMode" ] || exit 0

[ -n "$CWD" ] || CWD="$PWD"
[ -n "$SESSION" ] || exit 0

TASK="$(bouncer_my_task "$CWD" "$SESSION")" || exit 0

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
    bouncer_state_update "$TASK" --argjson items "$ITEMS" \
      --arg plan "$(jq -r '.tool_input.plan // empty' <<<"$INPUT")" \
      '.plan = $plan
       | .checklist = ($items | map({text: ., done: false}))' 2>/dev/null || true
  fi
fi
exit 0
