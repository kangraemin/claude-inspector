#!/usr/bin/env bash
# Stop — 엔진 본체.
# 모델이 응답을 끝내려는 순간 개입한다:
#   미처리 step 수행 → blocking 판정 → 통과면 다음 스테이지, 아니면 계속 일 시킴.
#
# current_stage를 쓰는 유일한 곳이다. 모델도 CLI도 못 바꾼다.

set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../engine/lib/common.sh"

INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

SESSION="$(jq -r '.session_id // empty' <<<"$INPUT")"
CWD="$(jq -r '.cwd // empty'        <<<"$INPUT")"
[ -n "$CWD" ] || CWD="$PWD"
[ -n "$SESSION" ] || exit 0

TASK="$(bouncer_my_task "$CWD" "$SESSION")" || exit 0      # 내 작업 없으면 관여 안 함
COMPILED="$(bouncer_compiled_file "$CWD")"
[ -f "$COMPILED" ] || exit 0

WORKFLOW="$(bouncer_state "$TASK" '.workflow')"
STAGE="$(bouncer_state "$TASK" '.current_stage')"
WORK_ROOT="$(bouncer_state "$TASK" '.work_root')"
[ -d "$WORK_ROOT" ] || WORK_ROOT="$CWD"
[ -n "$WORKFLOW" ] && [ -n "$STAGE" ] || exit 0
[ "$STAGE" = "cancelled" ] && exit 0

bouncer_touch_lock "$TASK"   # 하트비트 — 방치 판정의 근거
STAGE_JSON="$(bouncer_stage "$CWD" "$STAGE")"
[ -n "$STAGE_JSON" ] || exit 0

MAX_CONTINUE="$(bouncer_config max_continue 10 "$CWD")"
MAX_ATTEMPTS="$(bouncer_config max_attempts 3 "$CWD")"

# 직전 Stop에서 멈춤을 허용했다면, 지금 Stop이 왔다는 건 그 사이에 사용자 턴이 있었다는 뜻.
# (모델은 사용자 입력 없이 새 턴을 시작하지 못한다.) UserPromptSubmit hook이 필요 없는 이유다.
USER_TURN_HAPPENED="$(bouncer_state "$TASK" '.allowed_stop')"

INJECT=""      # 이번에 주입할 텍스트
FAILURES=""    # blocking 미충족 사유
HUMAN_WAIT=0   # 사람/승인 UI를 기다리는 중인가

add_inject()  { INJECT="${INJECT}${INJECT:+$'\n\n'}$1"; }
add_failure() { FAILURES="${FAILURES}${FAILURES:+$'\n'}- $1"; }

while IFS= read -r step; do
  [ -z "$step" ] && continue
  ID="$(jq -r '.id'       <<<"$step")"
  KIND="$(jq -r '.kind'   <<<"$step")"
  LABEL="$(jq -r '.label' <<<"$step")"
  BLOCKING="$(jq -r '.blocking // empty' <<<"$step")"
  OPTIONAL="$(jq -r '.optional' <<<"$step")"

  # 시작할 때 사용자가 끈 항목은 건너뛴다 (choices는 hook 전용 필드)
  if [ "$OPTIONAL" = "true" ]; then
    CHOSEN="$(jq -r --arg k "$ID" '.choices[$k] // false' "$TASK/state.json" 2>/dev/null)"
    [ "$CHOSEN" = "true" ] || continue
  fi

  DONE="$(jq -r --arg k "$ID" '.evidence[$k] // false' "$TASK/state.json" 2>/dev/null)"
  SHOWN="$(jq -r --arg k "$ID" '.shown[$k] // false'    "$TASK/state.json" 2>/dev/null)"

  if [ "$KIND" = "inject" ]; then
    if [ "$SHOWN" != "true" ]; then
      add_inject "$(jq -r '.text' <<<"$step")"
      bouncer_state_update "$TASK" --arg k "$ID" '.shown[$k] = true'
    fi
    [ -z "$BLOCKING" ] && continue
    # plan_approved / skill: 은 hook이 도구 사용을 직접 관찰한 증거다 — 사용자 턴을 따로 요구하지 않는다.
    # 반면 순수 inject blocking은 모델의 자기신고이므로 실제 사용자 턴이 있어야 인정한다.
    if [ "$DONE" = "true" ]; then
      case "$BLOCKING" in
        plan_approved|skill:*) continue ;;
        *) [ "$USER_TURN_HAPPENED" = "true" ] && continue ;;
      esac
    fi

    case "$BLOCKING" in
      plan_approved)
        add_failure "계획이 아직 승인되지 않았다 — ExitPlanMode 승인 필요 ($LABEL)"
        HUMAN_WAIT=1 ;;
      skill:*)
        add_failure "'${BLOCKING#skill:}' 스킬을 아직 실행하지 않았다 ($LABEL)" ;;
      *)
        if [ "$DONE" != "true" ]; then
          add_inject "→ 위를 마쳤으면 실행: bouncer done '$ID'   ($LABEL)"
        fi
        add_failure "사용자 확인 대기 중 ($LABEL)"
        HUMAN_WAIT=1 ;;
    esac
    continue
  fi

  # ── run ────────────────────────────────────────────────────
  [ "$DONE" = "true" ] && continue
  CMD="$(jq -r '.run'     <<<"$step")"
  BY="$(jq -r '.by'       <<<"$step")"
  TMO="$(jq -r '.timeout' <<<"$step")"

  if [ "$BY" = "engine" ]; then
    # 짧은 명령만 여기 온다 (컴파일에서 60초 상한 강제).
    if command -v timeout >/dev/null 2>&1; then
      OUT="$( cd "$WORK_ROOT" && timeout "$TMO" bash -lc "$CMD" 2>&1 )"; RC=$?
    else
      OUT="$( cd "$WORK_ROOT" && bash -lc "$CMD" 2>&1 )"; RC=$?
    fi
    TAIL="$(printf '%s' "$OUT" | tail -30)"
    if [ "$RC" -eq 0 ]; then
      bouncer_state_update "$TASK" --arg k "$ID" '.evidence[$k] = true'
      [ -n "$TAIL" ] && add_inject "[$LABEL] 통과 (exit 0)"$'\n'"$TAIL"
    elif [ -n "$BLOCKING" ]; then
      add_failure "$LABEL — \`$CMD\` 실패 (exit $RC)"
      add_inject "[$LABEL] 실패 (exit $RC)"$'\n'"$TAIL"
    fi
  else
    # 모델이 직접 실행한다. PostToolUse가 결과를 관찰해 evidence를 기록한다.
    if [ "$SHOWN" != "true" ]; then
      add_inject "다음 명령을 실행하고 결과를 확인해라 ($LABEL):"$'\n'"    $CMD"
      bouncer_state_update "$TASK" --arg k "$ID" '.shown[$k] = true'
    fi
    [ -n "$BLOCKING" ] && add_failure "$LABEL — \`$CMD\`를 아직 통과하지 못했다"
  fi
done < <(jq -c '.steps[]?' <<<"$STAGE_JSON")

# ─────────────────────────────────────────────────────────────
# 판정
# ─────────────────────────────────────────────────────────────
if [ -z "$FAILURES" ]; then
  # ── 전이 ──
  NEXT="$(bouncer_next_stage "$CWD" "$WORKFLOW" "$STAGE")"
  if [ -z "$NEXT" ]; then
    # 종단 도달 — lock 해제. 작업 문서는 남긴다.
    bouncer_state_update "$TASK" --arg t "$(date -u +%FT%TZ)" \
      '.finished_at = $t | .allowed_stop = false'
    rm -f "$TASK/.active"
    exit 0
  fi
  bouncer_state_update "$TASK" --arg n "$NEXT" --arg t "$(date -u +%FT%TZ)" \
    '.current_stage = $n
     | .continue_streak = 0
     | .allowed_stop = false
     | .history += [{stage:$n, at:$t}]'
  bouncer_block "✅ [$STAGE] 완료 → [$NEXT] 진입${INJECT:+$'\n\n'}$INJECT"
fi

# ── 미충족 ──
STREAK="$(bouncer_state "$TASK" '.continue_streak')"; [ -n "$STREAK" ] || STREAK=0

# ── on_fail 되돌아가기 ───────────────────────────────────────
# 이 스테이지가 파일 수정을 금지한다면 제자리 재시도는 무의미하다 → 1회 실패로 즉시 반송.
# 수정이 가능하면 max_attempts만큼 제자리에서 고쳐보고 그래도 안 되면 반송.
ON_FAIL="$(jq -r '.on_fail // empty' <<<"$STAGE_JSON")"
if [ -n "$ON_FAIL" ] && [ "$HUMAN_WAIT" != "1" ]; then
  CAN_FIX_HERE=1
  [ "$(jq -r '.forbid.edit_files // "null"' <<<"$STAGE_JSON")" != "null" ] && CAN_FIX_HERE=0
  ATTEMPTS="$(jq -r --arg s "$STAGE" '.stage_attempts[$s] // 0' "$TASK/state.json" 2>/dev/null)"
  [ -n "$ATTEMPTS" ] || ATTEMPTS=0
  ATTEMPTS=$(( ATTEMPTS + 1 ))
  bouncer_state_update "$TASK" --arg s "$STAGE" --argjson n "$ATTEMPTS" '.stage_attempts[$s] = $n'

  LIMIT="$MAX_ATTEMPTS"; [ "$CAN_FIX_HERE" = "0" ] && LIMIT=1
  if [ "$ATTEMPTS" -ge "$LIMIT" ] 2>/dev/null; then
    if [ "$ON_FAIL" = "abort" ]; then
      bouncer_state_update "$TASK" --arg t "$(date -u +%FT%TZ)" \
        '.current_stage = "cancelled" | .cancelled_at = $t'
      rm -f "$TASK/.active"
      jq -n --arg c "⛔ [$STAGE] 조건을 충족하지 못해 작업을 중단했다.

$FAILURES" '{hookSpecificOutput:{additionalContext:$c}}'
      exit 0
    fi
    # 되돌아갈 때 이 스테이지의 진행 기록을 지운다 — 돌아오면 처음부터 다시 검증한다.
    IDS="$(jq -c '[.steps[]?.id]' <<<"$STAGE_JSON")"
    bouncer_state_update "$TASK" --arg back "$ON_FAIL" --argjson ids "$IDS" \
      --arg s "$STAGE" --arg t "$(date -u +%FT%TZ)" '
        .current_stage = $back
        | .evidence       |= with_entries(select(.key as $k | ($ids | index($k)) | not))
        | .shown          |= with_entries(select(.key as $k | ($ids | index($k)) | not))
        | .stage_attempts[$s] = 0
        | .continue_streak = 0
        | .allowed_stop = false
        | .history += [{stage:$back, at:$t, returned_from:$s}]'
    bouncer_block "↩️ [$STAGE] 조건을 충족하지 못해 [$ON_FAIL] 단계로 되돌아간다.

미충족 조건:
$FAILURES${INJECT:+$'\n\n'}$INJECT"
  fi
fi

if [ "$HUMAN_WAIT" = "1" ]; then
  # 사람이 답해야 하는데 Stop을 막으면 답할 기회가 없다 — 반드시 멈추게 둔다.
  bouncer_state_update "$TASK" '.allowed_stop = true'
  exit 0
fi

if [ "$STREAK" -ge "$MAX_CONTINUE" ] 2>/dev/null; then
  bouncer_state_update "$TASK" '.allowed_stop = true | .continue_streak = 0'
  jq -n --arg c "⛔ ${MAX_CONTINUE}회 연속 진행했지만 [$STAGE] 단계를 벗어나지 못했다.

미충족 조건:
$FAILURES

AskUserQuestion으로 사용자에게 물어라:
  1. 계속 시도한다
  2. 접근을 바꾼다 (필요하면 이전 단계로 되돌린다)
  3. 이 조건을 이번 작업에서만 건너뛴다
  4. 작업을 중단한다" '{hookSpecificOutput:{additionalContext:$c}}'
  exit 0
fi

bouncer_state_update "$TASK" '.continue_streak = (.continue_streak // 0) + 1 | .allowed_stop = false'
bouncer_block "[$STAGE] 아직 끝나지 않았다.

미충족 조건:
$FAILURES${INJECT:+$'\n\n'}$INJECT"
