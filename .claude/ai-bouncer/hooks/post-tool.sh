#!/usr/bin/env bash
# PostToolUse — ExitPlanMode 가 승인되면 그 계획을 체크리스트로 옮긴다.
#               검사 명령을 Bash 로 직접 돌려 성공하면 그 step 의 통과로 기록한다.
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
case "$TOOL" in ExitPlanMode|Bash) ;; *) exit 0 ;; esac

[ -n "$CWD" ] || CWD="$PWD"
[ -n "$SESSION" ] || exit 0

TASK="$(bouncer_my_task "$CWD" "$SESSION")" || exit 0

# 검사 명령을 직접 돌려 성공했으면 bouncer run 과 같은 증거로 받는다.
# (PostToolUse 는 도구가 성공했을 때만 뜬다 — 실패는 PostToolUseFailure.)
# 먹맵 2026-10-23: 직접 돌려 통과한 e2e 를 기록용으로 6분 더 돌리게 했다.
if [ "$TOOL" = "Bash" ]; then
  [ "$(jq -r '.tool_response.interrupted // false' <<<"$INPUT" 2>/dev/null)" = "true" ] && exit 0
  command -v python3 >/dev/null 2>&1 || exit 0
  WORK_ROOT="$(bouncer_state "$TASK" '.work_root')"; [ -d "$WORK_ROOT" ] || WORK_ROOT="$CWD"
  WF="$(bouncer_state "$TASK" '.workflow')"
  STEPS="$(while IFS= read -r st; do [ -n "$st" ] && bouncer_stage "$CWD" "$st" \
             | jq -c '.steps[]? | select(.kind == "run") | {id, run}'; done < <(bouncer_chain "$CWD" "$WF") \
           | jq -s -c '.')"
  [ -n "$STEPS" ] && [ "$STEPS" != "[]" ] || exit 0
  HITS="$(jq -n -c --arg cmd "$(jq -r '.tool_input.command // ""' <<<"$INPUT")" --arg w "$WORK_ROOT" \
            --argjson steps "$STEPS" --argjson sc "$(jq -c '.scope // {}' "$TASK/state.json")" \
            '{cmd:$cmd, work_root:$w, steps:$steps, scopes:$sc}' \
          | python3 -B "$(dirname "${BASH_SOURCE[0]}")/../engine/lib/match_run.py" 2>/dev/null)"
  [ -n "$HITS" ] || exit 0
  TREE="$(bouncer_evidence_tree "$TASK" "$WORK_ROOT")"
  MSG=""
  while IFS=$'\t' read -r id args; do
    [ -n "$id" ] || continue
    bouncer_state_update "$TASK" --arg k "$id" --arg t "$TREE" --argjson a "$args" '
      .evidence[$k] = true | .evidence_tree[$k] = $t
      | del(.failed_scope[$k]) | del(.attempts[$k]) | del(.broken[$k])
      | if ((.scope[$k] // []) | length) == 0 and ($a | length) > 0 then .scope[$k] = $a else . end' || continue
    MSG="${MSG}${MSG:+, }$id"
  done <<<"$HITS"
  [ -n "$MSG" ] && jq -n --arg c "[ai-bouncer] 직접 실행한 검사를 통과로 기록했다: $MSG — bouncer run 으로 다시 돌릴 필요 없다." \
    '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$c}}'
  exit 0
fi

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
