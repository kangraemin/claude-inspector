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

# 이 Stop이 직전 Stop hook의 차단 때문에 재진입한 것이면 true다.
# 여기서 또 차단하면 사용자 개입 없이 영원히 도는 구간이 생긴다.
# continue_streak 상한이 1차 방어지만, 그 카운터가 어떤 이유로 리셋되면
# 그것만으로는 못 막는다. 그래서 재진입 자체를 별도로 센다.
REENTRY="$(jq -r '.stop_hook_active // false' <<<"$INPUT")"
[ -n "$CWD" ] || CWD="$PWD"
[ -n "$SESSION" ] || exit 0

TASK="$(bouncer_my_task "$CWD" "$SESSION")" || exit 0      # 내 작업 없으면 관여 안 함
COMPILED="$(bouncer_compiled_file "$CWD")"
# 진단은 guarded_block 이 정의된 뒤에 한다 — 직접 block 을 내보내면
# 상한 카운터를 안 거쳐 세션이 영원히 안 돌아온다 (30/30 차단이 재현됐다).
CONFIG_BROKEN=0
[ ! -f "$COMPILED" ] || jq -e . "$COMPILED" >/dev/null 2>&1 || CONFIG_BROKEN=1
[ -f "$COMPILED" ] || CONFIG_BROKEN=1

WORKFLOW="$(bouncer_state "$TASK" '.workflow')"
STAGE="$(bouncer_state "$TASK" '.current_stage')"
WORK_ROOT="$(bouncer_state "$TASK" '.work_root')"
[ -n "$WORK_ROOT" ] || WORK_ROOT="$CWD"
STATE_BROKEN=0
jq -e . "$TASK/state.json" >/dev/null 2>&1 || STATE_BROKEN=1
if [ "$STATE_BROKEN" = 0 ]; then
  [ -n "$WORKFLOW" ] && [ -n "$STAGE" ] || exit 0
fi
[ "$STAGE" = "cancelled" ] && exit 0

bouncer_touch_lock "$TASK"   # 하트비트 — 방치 판정의 근거
STAGE_JSON="$(bouncer_stage "$CWD" "$STAGE")"
# 빈 값이면 조용히 나가면 안 된다 — 작업이 영원히 멈추고 잠금이 남는다.
# (워크플로우 이름 변경은 아래 전이 단계에서 잡히지만, 스테이지 삭제는 여기서 잡아야 한다)
if [ -z "$STAGE_JSON" ]; then
  STAGE_MISSING=1
else
  STAGE_MISSING=0
fi

MAX_CONTINUE="$(bouncer_config max_continue 10 "$CWD")"
MAX_ATTEMPTS="$(bouncer_config max_attempts 3 "$CWD")"
MAX_LOOPS="$(bouncer_config max_loops 3 "$CWD")"

# 사람이 실제로 답했는지는 UserPromptSubmit hook이 올린 카운터로 판정한다.
# allowed_stop 만 보면, 한 번 사람 대기 상태가 됐던 작업에서 모델이 같은 턴에
# `bouncer done` 을 쳐도 통과한다 — 게이트가 자기 보고로 전락한다.
UT_NOW="$(bouncer_state "$TASK" '.user_turns')"; [ -n "$UT_NOW" ] || UT_NOW=0
UT_MARK="$(bouncer_state "$TASK" '.user_turns_at_wait')"; [ -n "$UT_MARK" ] || UT_MARK=-1
USER_TURN_HAPPENED=false
[ "$UT_MARK" -ge 0 ] 2>/dev/null && [ "$UT_NOW" -gt "$UT_MARK" ] 2>/dev/null && USER_TURN_HAPPENED=true

INJECT=""      # 이번에 주입할 텍스트
FAILURES=""    # blocking 미충족 사유
HUMAN_WAIT=0   # 사람/승인 UI를 기다리는 중인가
HARD_FAIL=0    # 사람과 무관하게 실패한 조건이 있는가 (run 게이트 등)
PENDING_DONE=0 # 모델이 아직 done 표시를 안 했을 뿐인가 (실패가 아니라 진행 중)

add_inject()  { INJECT="${INJECT}${INJECT:+$'\n\n'}$1"; }

# 전이·반송 등 어떤 경로로 차단하든 여기를 지난다. 상한을 넘으면 세션을 돌려준다.
# 전이가 continue_streak 을 리셋해도 이 카운터는 리셋되지 않는다.
MAX_BLOCKS=$(( MAX_CONTINUE * 2 + 4 ))
guarded_block() {
  local n
  n="$(jq -r '.blocks_total // 0' "$TASK/state.json" 2>/dev/null)"; [ -n "$n" ] || n=""
  if [ -z "$n" ] || ! [ "$n" -eq "$n" ] 2>/dev/null; then
    # state.json 을 못 읽는 상황에서도 상한은 살아야 한다. 카운터를 state 에만
    # 두면, 상태가 깨진 바로 그 경우에 안전밸브가 원리상 작동하지 않는다
    # (40회 연속 차단이 재현됐다). 별도 파일로 센다.
    n="$(cat "$TASK/.blocks" 2>/dev/null)"; [ -n "$n" ] || n=0
    n=$(( n + 1 )); printf '%s' "$n" > "$TASK/.blocks" 2>/dev/null
  else
    n=$(( n + 1 ))
  fi
  if [ "$n" -gt "$MAX_BLOCKS" ] 2>/dev/null; then
    rm -f "$TASK/.blocks"
    bouncer_state_update "$TASK" '.blocks_total = 0 | .continue_streak = 0 | .reentry_count = 0
      | .allowed_stop = true | .returned_to = null | .returned_tree = null'
    local _head="⛔ 사용자 개입 없이 ${MAX_BLOCKS}번 연속으로 진행했다. 세션을 돌려준다."
    case "$1" in
      "✅"*) _head="ℹ️ ${MAX_BLOCKS}번 연속으로 진행했다. 여기서 한 번 사용자에게 돌려준다." ;;
    esac
    jq -n --arg c "$_head

$1

AskUserQuestion으로 물어라 (도구가 없으면 텍스트로 제시하고 답을 기다려라):
  1. 계속 진행한다
  2. 접근을 바꾼다
  3. 작업을 중단한다 (bouncer cancel)" \
      '{hookSpecificOutput:{hookEventName:"Stop", additionalContext:$c}}'
    exit 0
  fi
  bouncer_state_update "$TASK" --argjson n "$n" '.blocks_total = $n'
  bouncer_block "$1"
}

if [ "${STATE_BROKEN:-0}" = 1 ]; then
  guarded_block "⛔ [ai-bouncer] 작업 상태 파일이 손상됐다.
진행 상황을 알 수 없어 단계를 넘길 수 없다.
  · 작업을 포기한다: bouncer cancel"
fi
if [ "${CONFIG_BROKEN:-0}" = 1 ]; then
  guarded_block "⛔ [ai-bouncer] 워크플로우 설정을 읽을 수 없다.
규칙을 알 수 없는 상태에서는 단계를 넘길 수 없다.
  · \`bouncer check\` 로 workflow.yaml 을 확인하라 (yaml 이 멀쩡하면 다음 세션 시작 때 다시 컴파일된다)
  · 작업을 포기한다: bouncer cancel"
fi

# 엔진이 이 스테이지를 포기했다고 기록한다. `bouncer skip` 은 이 표시가 있어야 열린다.
# 지금 막고 있는 조건이 다른 스테이지 소속일 수도 있어서(반송 뒤가 그렇다)
# 미충족 step 이 속한 스테이지도 같이 표시한다.
# 엔진이 포기하며 **실제로 제안한 step id** 를 기록한다. `bouncer skip` 은
# 이 목록에 있는 것만 열어주고, 쓰면 소모한다.
# 스테이지 단위로 표시하면 (a) 제안하지 않은 게이트까지 열리고
# (b) 한 번 쓰면 스테이지가 통째로 닫혀 두 번째 제안이 실패했으며
# (c) 다음 전이가 표시를 지워 "시킨 대로 했더니 닫히는" 상황이 됐다.
offer_skip() {
  [ -n "$BLOCKING_IDS" ] || return 0
  local ids
  ids="$(printf '%s' "$BLOCKING_IDS" | jq -R -s 'split("\n") | map(select(length > 0))')"
  bouncer_state_update "$TASK" --argjson ids "$ids" \
    '.skip_allowed = ((.skip_allowed // []) + $ids | unique)'
  return 0
}

if [ "$STAGE_MISSING" = 1 ]; then
  guarded_block "⛔ [ai-bouncer] 진행 중인 단계 '$STAGE' 가 workflow.yaml에 없다.
작업 도중 삭제되었거나 이름이 바뀐 것으로 보인다.

  · workflow.yaml에서 '$STAGE' 를 되돌린다
  · 이 작업을 포기한다: bouncer cancel"
fi

# 작업 트리가 사라졌는데 조용히 프로젝트로 폴백하면 검증 대상이 예고 없이 바뀐다.
# (빈 worktree는 항상 클린 트리라 finalize 게이트가 무조건 열린다)
if [ ! -d "$WORK_ROOT" ]; then
  guarded_block "⛔ [ai-bouncer] 이 작업의 작업 트리가 사라졌다: $WORK_ROOT
병렬 작업용 worktree가 삭제된 것으로 보인다.
검증과 커밋을 어느 트리에서 해야 할지 알 수 없어 진행할 수 없다.

  · 작업을 포기한다:        bouncer cancel
  · worktree를 되살린다:    git worktree prune && git worktree add $WORK_ROOT $(bouncer_state "$TASK" '.worktree.branch')
    (prune 없이 add만 하면 '이미 등록된 worktree' 라며 실패한다)"
fi
N_FAIL=0; N_PENDING=0  # 미충족 조건 수 / 그중 done 표시만 남은 수
add_failure() { FAILURES="${FAILURES}${FAILURES:+$'\n'}- $1"; N_FAIL=$((N_FAIL+1)); }
# 막고 있는 step 의 id 를 모아둔다. "건너뛴다"를 제안하면서 id 를 안 주면
# 모델이 compiled.json 을 직접 읽지 않는 한 그 제안을 실행할 수 없다.
# step id 는 `<stage>/<label>` 이고 라벨에 공백이 있다. 공백으로 이어붙였다가
# 인용 없이 뿌려서 제안이 전부 쪼개졌다 — 다섯 줄 모두 실행 불가였다.
BLOCKING_IDS=""
add_blocking_id() {
  case $'\n'"$BLOCKING_IDS"$'\n' in *$'\n'"$1"$'\n'*) return 0 ;; esac
  BLOCKING_IDS="${BLOCKING_IDS}${BLOCKING_IDS:+$'\n'}$1"
}
# 제안은 그대로 복사해서 실행할 수 있어야 한다.
# (`printf '%s' | while read` 는 끝에 개행이 없어 마지막 줄을 통째로 버린다)
skip_hint() {
  [ -n "$BLOCKING_IDS" ] || { printf '       (막고 있는 step을 특정하지 못했다 — bouncer status 참고)'; return; }
  while IFS= read -r _i; do
    [ -n "$_i" ] && printf "       bouncer skip '%s'\n" "$_i"
  done <<< "$BLOCKING_IDS"
}

while IFS= read -r step; do
  [ -z "$step" ] && continue
  ID="$(jq -r '.id'       <<<"$step")"
  KIND="$(jq -r '.kind'   <<<"$step")"
  LABEL="$(jq -r '.label' <<<"$step")"
  BLOCKING="$(jq -r '.blocking // empty' <<<"$step")"
  OPTIONAL="$(jq -r '.optional' <<<"$step")"

  # 사용자가 끈 항목은 건너뛴다.
  #  · choices  — 시작할 때 --off 로 끈 optional 항목
  #  · skipped  — 엔진이 포기한 뒤 `bouncer skip` 으로 이번 작업만 면제한 항목
  # jq의 `//` 는 false를 "없음"으로 보므로 has()로 물어야 한다.
  if [ "$(jq -r --arg k "$ID" '.skipped[$k] // false' "$TASK/state.json" 2>/dev/null)" = "true" ]; then
    continue
  fi
  if [ "$OPTIONAL" = "true" ]; then
    CHOSEN="$(jq -r --arg k "$ID" \
      'if (.choices | has($k)) then .choices[$k] else true end' "$TASK/state.json" 2>/dev/null)"
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
        # 사람 확인 게이트는 없앴다 — inject 의 blocking: true 도 모델의 done 표시로 통과한다.
        *) continue ;;
      esac
    fi

    case "$BLOCKING" in
      plan_approved)
        add_failure "계획이 아직 승인되지 않았다 — ExitPlanMode 승인 필요 ($LABEL)"; add_blocking_id "$ID"
        HUMAN_WAIT=1 ;;
      skill:*)
        add_failure "'${BLOCKING#skill:}' 스킬을 아직 실행하지 않았다 ($LABEL)"; add_blocking_id "$ID" ;;
      checklist)
        # 자기보고가 아니다 — 엔진이 항목 수를 센다.
        CL_N="$(jq -r '(.checklist // []) | length' "$TASK/state.json" 2>/dev/null)"
        CL_LEFT="$(jq -r '[(.checklist // [])[] | select(.done | not)] | length' \
                    "$TASK/state.json" 2>/dev/null)"
        CL_TURN="$(jq -r '.checklist_turn // -1' "$TASK/state.json" 2>/dev/null)"
        if [ "${CL_N:-0}" = 0 ]; then
          add_failure "할 일 목록이 비어 있다 ($LABEL) — \`bouncer todo add\` 로 채워라"
          add_blocking_id "$ID"
        elif [ "${CL_LEFT:-1}" != 0 ]; then
          add_failure "남은 항목 ${CL_LEFT}/${CL_N}개 ($LABEL) — \`bouncer todo\` 로 확인"
          add_blocking_id "$ID"
        else
          # 예전엔 "목록을 세운 턴에 전부 체크하면 사용자 확인"을 요구했다.
          # 그 탓에 done 전인데도 모델이 매번 사용자에게 승인을 물었다 — 제거.
          bouncer_state_update "$TASK" --arg k "$ID" '.evidence[$k] = true'
          continue
        fi ;;
      *)
        # 사람을 기다리지 않는다 — 모델이 할 일을 마치고 직접 표시한다.
        # (예전엔 inject + blocking: true 가 "사용자 확인 대기"였다. 작업 도중 매번
        #  승인을 묻게 만들어 없앴다. true 와 done 은 이제 같다.)
        add_inject "→ 위를 마쳤으면 실행: bouncer done '$ID'   ($LABEL)"
        add_failure "아직 완료 표시 안 됨 ($LABEL)"; add_blocking_id "$ID"
        PENDING_DONE=1; N_PENDING=$((N_PENDING+1)) ;;

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
    # 종료코드만 알려주면 무엇을 고쳐야 할지 알 수 없다.
    if [ "$RC" -ne 0 ] && printf '%s' "$CMD" | grep -q 'git status --porcelain'; then
      TAIL="$TAIL"$'\n'"현재 워킹트리:"$'\n'"$(git -C "$WORK_ROOT" status --porcelain 2>/dev/null | head -20)"
    fi
    if [ "$RC" -eq 0 ]; then
      bouncer_state_update "$TASK" --arg k "$ID" '.evidence[$k] = true'
      [ -n "$TAIL" ] && add_inject "[$LABEL] 통과 (exit 0)"$'\n'"$TAIL"
    elif [ -n "$BLOCKING" ]; then
      add_failure "$LABEL — \`$CMD\` 실패 (exit $RC)"; add_blocking_id "$ID"; HARD_FAIL=1
      add_inject "[$LABEL] 실패 (exit $RC)"$'\n'"$TAIL"
    fi
  else
    # 모델이 직접 실행한다. PostToolUse가 결과를 관찰해 evidence를 기록한다.
    if [ "$SHOWN" != "true" ]; then
      # 명령을 직접 치라고 하면 결과가 증거로 남지 않아 영원히 미충족이 된다.
      # 엔진이 명령을 소유하므로 bouncer run 으로 돌려야 종료코드가 기록된다.
      add_inject "$LABEL — 아래를 실행해라 (명령은 엔진이 갖고 있다):"$'\n'"    bouncer run '$ID'"
      bouncer_state_update "$TASK" --arg k "$ID" '.shown[$k] = true'
    fi
    if [ -n "$BLOCKING" ]; then
      add_failure "$LABEL — 아직 통과하지 못했다 (\`bouncer run '$ID'\`)"
      add_blocking_id "$ID"
    fi
  fi
done < <(jq -c '.steps[]?' <<<"$STAGE_JSON")

# ─────────────────────────────────────────────────────────────
# 판정
# ─────────────────────────────────────────────────────────────
if [ -z "$FAILURES" ]; then
  # 반송돼 온 스테이지라면, 뭔가 달라졌을 때만 다시 내보낸다.
  # 그러지 않으면 조건 없는 스테이지를 사이에 두고 같은 검사를 무한히 반복한다.
  RET_TO="$(bouncer_state "$TASK" '.returned_to')"
  RET_FROM="$(bouncer_state "$TASK" '.returned_from')"
  # 반송된 상태에서는 현재 스테이지의 조건이 전부 통과라 FAILURES 가 비어 있다.
  # 정작 막고 있는 건 되돌려보낸 스테이지의 게이트이므로 거기서 id 를 가져온다.
  # (이 백필이 아래 포기 분기보다 **앞에** 있어야 한다 — 뒤에 두면 죽은 코드다)
  if [ -z "$BLOCKING_IDS" ] && [ -n "$RET_FROM" ]; then
    while IFS= read -r _bid; do
      [ -n "$_bid" ] && add_blocking_id "$_bid"
    done < <(bouncer_stage "$CWD" "$RET_FROM" | jq -r '.steps[]? | select(.blocking) | .id')
  fi
  if [ -n "$RET_TO" ] && [ "$RET_TO" = "$STAGE" ]; then
    RET_TREE="$(bouncer_state "$TASK" '.returned_tree')"
    NOW_TREE="$(bouncer_tree_hash "$WORK_ROOT")"
    if [ -n "$RET_TREE" ] && [ "$RET_TREE" = "$NOW_TREE" ]; then
      bouncer_state_update "$TASK" '.continue_streak = (.continue_streak // 0) + 1'
      NS="$(bouncer_state "$TASK" '.continue_streak')"; [ -n "$NS" ] || NS=1
      # 직전 차단 뒤 도구를 하나도 안 쓰고 또 멈추려 한다 = 고칠 게 없다고 판단한 것이다.
      # 다시 막아봐야 같은 답만 상한까지 반복하므로 (지운 스크립트를 부르는 게이트 등)
      # 그 자리에서 사용자에게 넘긴다.
      _seq_now="$(cat "$TASK/.tool_seq" 2>/dev/null)"; case "$_seq_now" in ''|*[!0-9]*) _seq_now=0 ;; esac
      _seq_blk="$(cat "$TASK/.tool_seq_at_block" 2>/dev/null)"; case "$_seq_blk" in ''|*[!0-9]*) _seq_blk=-1 ;; esac
      _idle=0; [ "$REENTRY" = "true" ] && [ "$_seq_now" = "$_seq_blk" ] && _idle=1
      # 여기서 그냥 막으면 아래 상한 검사에 영영 도달하지 못한다.
      # 고칠 의사가 없거나 고칠 수 없는 상황이면 세션을 사용자에게 돌려줘야 한다.
      if [ "$_idle" = "1" ] || [ "$NS" -ge "$MAX_CONTINUE" ] 2>/dev/null; then
        bouncer_state_update "$TASK" \
          '.allowed_stop = true | .continue_streak = 0 | .returned_to = null | .returned_tree = null'
        jq -n --arg c "${INJECT:+$INJECT$'\n\n'}⛔ [$STAGE] 되돌아온 뒤 ${NS}번 동안 작업 트리가 그대로다$([ "$_idle" = "1" ] && printf ' (직전 차단 뒤 도구 호출 0회)').
고칠 수 없거나 고칠 것이 없는 상태로 보인다. 사용자에게 넘긴다.

직전 실패:
$(bouncer_state "$TASK" '.last_failure')

AskUserQuestion으로 물어라 (도구가 없으면 텍스트로 제시하고 답을 기다려라):
  1. 접근을 바꿔서 다시 시도한다
  2. 이 조건을 이번 작업에서만 건너뛴다:
$(skip_hint)
  3. 작업을 중단한다 (bouncer cancel)" '{hookSpecificOutput:{hookEventName:"Stop", additionalContext:$c}}'
        offer_skip
        exit 0
      fi
      printf '%s' "$_seq_now" > "$TASK/.tool_seq_at_block" 2>/dev/null || true
      guarded_block "[$STAGE] 되돌아온 뒤 작업 트리가 그대로다 — 아무것도 바뀌지 않았다. (${NS}/${MAX_CONTINUE})

이대로 다시 검증에 보내면 같은 결과가 나온다. 무엇이 틀렸는지 다시 보고 실제로 고쳐라.
직전 실패:
$(bouncer_state "$TASK" '.last_failure')${INJECT:+$'\n\n'}$INJECT"
    fi
    # returned_from 도 같이 지운다. 안 지우면 반송 판정이 계속 켜져 있다.
    bouncer_state_update "$TASK" '.returned_to = null | .returned_tree = null | .returned_from = null'
  fi

  # ── 전이 ──
  NEXT="$(bouncer_next_stage "$CWD" "$WORKFLOW" "$STAGE")"
  # 다음 단계가 비었다고 곧장 "끝"으로 보면 안 된다. 작업 도중 workflow.yaml에서
  # 그 워크플로우나 단계를 지우거나 이름을 바꿔도 똑같이 빈 값이 나오는데,
  # 그러면 finalize(커밋·클린 트리 게이트)가 통째로 건너뛰어지고 작업이 "완료"된다.
  if [ -z "$NEXT" ] && ! bouncer_is_last_stage "$CWD" "$WORKFLOW" "$STAGE"; then
    guarded_block "⛔ [ai-bouncer] 진행 중인 작업의 체인을 찾을 수 없다.
워크플로우 '$WORKFLOW'의 단계 '$STAGE' 가 workflow.yaml에 없다 —
작업 도중에 이름이 바뀌었거나 삭제된 것으로 보인다.

되돌리는 방법은 둘 중 하나다:
  · workflow.yaml에서 '$WORKFLOW' / '$STAGE' 를 원래대로 되돌린다
  · 이 작업을 포기한다: bouncer cancel"
  fi
  if [ -z "$NEXT" ]; then
    # 병렬 작업이면 머지가 남아 있다. 여기서 잠금을 풀면 `worktree finalize` 가
    # 작업을 못 찾아(need_task는 .active로 찾는다) 커밋이 브랜치에 갇힌다.
    WT_PATH="$(bouncer_state "$TASK" '.worktree.path')"
    if [ -n "$WT_PATH" ] \
       && [ "$(bouncer_state "$TASK" '.worktree.merged')" != "true" ]; then
      # finished_at 을 여기서 찍으면 scan/resume 의 미완 목록에서 빠져,
      # 이 시점에 세션이 죽으면 커밋이 브랜치에 갇힌 채 아무도 못 찾는다.
      guarded_block "✅ 작업은 끝났지만 아직 base 브랜치에 합쳐지지 않았다.

    bouncer worktree finalize

이걸 실행해야 $(bouncer_state "$TASK" '.worktree.branch') 가 base로 FF 머지되고
worktree가 정리된다. 지금 멈추면 커밋이 그 브랜치에 갇힌다."
    fi
    # 종단 도달 — lock 해제. 작업 문서는 남긴다.
    # 실패하면 .active 만 지워져 끝난 작업이 영구히 미완(ORPHAN)으로 뜬다
    if ! bouncer_state_update "$TASK" --arg t "$(date -u +%FT%TZ)" \
      '.finished_at = $t | .allowed_stop = false'; then
      guarded_block "⛔ [ai-bouncer] 완료를 기록하지 못했다 (상태 파일 잠금 경합).
잠시 뒤 다시 시도하면 된다."
    fi
    rm -f "$TASK/.active"
    [ -n "$INJECT" ] && jq -n --arg c "$INJECT" \
      '{hookSpecificOutput:{hookEventName:"Stop", additionalContext:$c}}'
    exit 0
  fi
  # 다음 스테이지의 지시를 지금 함께 전달한다. 그러지 않으면 blocking 없는
  # 스테이지는 "진입 → 다음 Stop에서 즉시 통과"라 지시를 받는 턴이 없다.
  NEXT_TXT="$(bouncer_stage "$CWD" "$NEXT" \
    | jq -r --slurpfile st "$TASK/state.json" \
        '[.steps[]? | .id as $sid | select(.kind=="inject")
          | select(($st[0].skipped[$sid] // false) | not)
          | select((.optional | not)
                   or (if ($st[0].choices | has($sid)) then $st[0].choices[$sid] else true end))
          | .text] | join("\n\n")')"
  if [ -n "$NEXT_TXT" ]; then
    while IFS= read -r nid; do
      [ -n "$nid" ] && bouncer_state_update "$TASK" --arg k "$nid" '.shown[$k] = true'
    done < <(bouncer_stage "$CWD" "$NEXT" | jq -r --slurpfile st "$TASK/state.json" \
      '.steps[]? | .id as $sid | select(.kind=="inject")
       | select(($st[0].skipped[$sid] // false) | not)
       | select((.optional | not)
                or (if ($st[0].choices | has($sid)) then $st[0].choices[$sid] else true end)) | $sid')
  fi
  # 갱신이 실패하면(잠금 경합 등) 단계는 그대로인데 "완료" 를 보고하게 된다.
  # 모델은 다음 단계라고 믿고 forbid 는 이전 단계 것을 강제한다.
  if ! bouncer_state_update "$TASK" --arg n "$NEXT" --arg t "$(date -u +%FT%TZ)" --arg s "$STAGE" \
    '.current_stage = $n
     | .continue_streak = 0
     | .reentry_count = 0
     | .allowed_stop = false
     | .user_turns_at_wait = null
     | .returned_from = null
     | .history += [{stage:$n, at:$t}]'; then
    guarded_block "⛔ [ai-bouncer] 단계 전이를 기록하지 못했다 (상태 파일 잠금 경합).
잠시 뒤 다시 시도하면 된다. 계속 반복되면 \`bouncer status\` 로 확인하라."
  fi
  # 이 턴에 쌓인 지시·게이트 출력을 함께 내보낸다. 버리면 `.shown` 은 이미
  # true 라 반송 뒤 재전달이 영영 안 되고, run 게이트 출력도 늘 사라진다.
  guarded_block "${INJECT:+$INJECT$'\n\n'}✅ [$STAGE] 완료 → [$NEXT] 진입${NEXT_TXT:+$'\n\n'}$NEXT_TXT"
fi

# ── 미충족 ──
STREAK="$(bouncer_state "$TASK" '.continue_streak')"; [ -n "$STREAK" ] || STREAK=0

# ── on_fail 되돌아가기 ───────────────────────────────────────
# 이 스테이지가 **모든** 파일 수정을 금지한다면 제자리 재시도는 무의미하다 → 1회로 반송.
# 글로브 배열은 스코프 밖만 막는 것이라 제자리에서 고칠 수 있다 —
# 여기서 배열까지 "수정 불가"로 보면 max_attempts가 무시되고 max_loops만 빨리 탄다.
ON_FAIL="$(jq -r '.on_fail // empty' <<<"$STAGE_JSON")"
# 사람을 기다리는 중이면 반송하지 않는다 — 답할 기회를 뺏기 때문이다.
# 다만 사람과 무관한 조건(run 게이트)이 실패했다면 그건 반송 사유다.
# 예전엔 HUMAN_WAIT 하나로 막아서, 기본 default.yaml 의 verify 처럼
# 사람 확인이 함께 있는 스테이지는 on_fail 이 **절대** 발동하지 않았다.
# 아직 done 표시를 안 한 것은 실패가 아니라 진행 중이다 — 그걸로 반송하면
# 검증이 오래 걸리는 작업이 몇 번 멈췄다는 이유만으로 구현 단계로 쫓겨난다.
if [ -n "$ON_FAIL" ] && { [ "$HARD_FAIL" = "1" ] || { [ "$HUMAN_WAIT" != "1" ] && [ "$PENDING_DONE" != "1" ]; }; }; then
  CAN_FIX_HERE=1
  [ "$(jq -r '.forbid.edit_files' <<<"$STAGE_JSON")" = "true" ] && CAN_FIX_HERE=0
  # 사람 확인 게이트가 함께 미충족이면 즉시 반송하면 안 된다 — 답할 기회를
  # 한 번도 안 주고 되돌려보내게 된다 (README 의 verify 예제가 정확히 그 모양).
  [ "$HUMAN_WAIT" = "1" ] && CAN_FIX_HERE=1
  ATTEMPTS="$(jq -r --arg s "$STAGE" '.stage_attempts[$s] // 0' "$TASK/state.json" 2>/dev/null)"
  [ -n "$ATTEMPTS" ] || ATTEMPTS=0
  ATTEMPTS=$(( ATTEMPTS + 1 ))
  [ "$ATTEMPTS" -le $(( MAX_ATTEMPTS + 1 )) ] 2>/dev/null \
    && bouncer_state_update "$TASK" --arg s "$STAGE" --argjson n "$ATTEMPTS" '.stage_attempts[$s] = $n'

  LIMIT="$MAX_ATTEMPTS"; [ "$CAN_FIX_HERE" = "0" ] && LIMIT=1
  if [ "$ATTEMPTS" -ge "$LIMIT" ] 2>/dev/null; then
    if [ "$ON_FAIL" = "abort" ]; then
      bouncer_state_update "$TASK" --arg t "$(date -u +%FT%TZ)" \
        '.current_stage = "cancelled" | .cancelled_at = $t'
      rm -f "$TASK/.active"
      jq -n --arg c "⛔ [$STAGE] 조건을 충족하지 못해 작업을 중단했다.

$FAILURES" '{hookSpecificOutput:{hookEventName:"Stop", additionalContext:$c}}'
      exit 0
    fi
    # 왕복 횟수는 전이가 리셋하지 않는다. 리셋하면 A→B→A→B 로 영원히 돈다.
    bouncer_state_update "$TASK" --arg f "$FAILURES" '.last_failure = $f'
    PAIR="$STAGE->$ON_FAIL"
    LOOPS="$(jq -r --arg k "$PAIR" '.loops[$k] // 0' "$TASK/state.json" 2>/dev/null)"
    [ -n "$LOOPS" ] && [ "$LOOPS" != "null" ] || LOOPS=0
    if [ "$(( LOOPS + 1 ))" -gt "$MAX_LOOPS" ] 2>/dev/null; then
      # 이미 상한이면 카운터를 더 올리지 않는다 — 숫자가 실제 왕복 횟수와 어긋난다.
      bouncer_state_update "$TASK" \
        '.allowed_stop = true | .continue_streak = 0 | .reentry_count = 0'
      jq -n --arg c "${INJECT:+$INJECT$'\n\n'}⛔ [$STAGE] ↔ [$ON_FAIL] 사이를 ${LOOPS}번 왕복했다.
같은 자리를 돌고 있으므로 더 밀지 않고 사용자에게 넘긴다.

미충족 조건:
$FAILURES

AskUserQuestion으로 물어라 (도구가 없으면 텍스트로 제시하고 답을 기다려라):
  1. 접근을 바꿔서 다시 시도한다
  2. 이 조건을 이번 작업에서만 건너뛴다:
$(skip_hint)
  3. 작업을 중단한다 (bouncer cancel)" '{hookSpecificOutput:{hookEventName:"Stop", additionalContext:$c}}'
      offer_skip
      exit 0
    fi
    LOOPS=$(( LOOPS + 1 ))

    # 되돌아갈 때, 반송 대상부터 실패 스테이지까지의 진행 기록을 전부 지운다.
    # 실패 스테이지 것만 지우면 사이 스테이지의 게이트가 "한 번 통과했으니 통과"로
    # 영원히 건너뛰어진다 — 그 사이에 코드가 바뀌었는데도.
    IDS="$(
      { CH="$(bouncer_chain "$CWD" "$WORKFLOW")"
        started=0
        while IFS= read -r st; do
          [ "$st" = "$ON_FAIL" ] && started=1
          [ "$started" = 1 ] && bouncer_stage "$CWD" "$st" | jq -r '.steps[]?.id'
          [ "$st" = "$STAGE" ] && break
        done <<< "$CH"
      } | jq -R -s 'split("\n") | map(select(length > 0))'
    )"
    # 되돌려 보낸 시점의 작업 트리를 기억해둔다. 아무것도 안 바뀌었는데
    # 다시 전진시키면 같은 검사를 같은 코드에 돌리는 헛바퀴가 된다.
    TREE="$(bouncer_tree_hash "$WORK_ROOT")"
    # 전진 전이와 같은 이유로 rc 를 봐야 한다. 갱신이 실패하면 단계는
    # 그대로인데 "되돌아간다" 를 보고하고, loops·evidence 초기화도 유실된다.
    if ! bouncer_state_update "$TASK" --arg back "$ON_FAIL" --argjson ids "$IDS" \
      --arg s "$STAGE" --arg t "$(date -u +%FT%TZ)" --argjson n "$LOOPS" --arg tree "$TREE" --arg pair "$PAIR" '
        .current_stage = $back
        | .returned_tree = $tree
        | .returned_to = $back
        | .returned_from = $s
        | .loops[$pair] = $n
        | .evidence       |= with_entries(select(.key as $k | ($ids | index($k)) | not))
        | .shown          |= with_entries(select(.key as $k | ($ids | index($k)) | not))
        | .stage_attempts[$s] = 0
        | .continue_streak = 0
        | .allowed_stop = false
        | .history += [{stage:$back, at:$t, returned_from:$s}]'; then
      guarded_block "⛔ [ai-bouncer] 반송을 기록하지 못했다 (상태 파일 잠금 경합).
잠시 뒤 다시 시도하면 된다."
    fi
    guarded_block "↩️ [$STAGE] 조건을 충족하지 못해 [$ON_FAIL] 단계로 되돌아간다. (${LOOPS}/${MAX_LOOPS}회)

미충족 조건:
$FAILURES${INJECT:+$'\n\n'}$INJECT"
  fi
fi

if [ "$HUMAN_WAIT" = "1" ]; then
  # 사람이 답해야 하는데 Stop을 막으면 답할 기회가 없다 — 멈추게 둔다.
  # 다만 지시와 미충족 사유는 반드시 전달해야 한다. 여기서 버리면
  # 이 스테이지의 프롬프트가 모델에게 한 번도 도달하지 않는다.
  # 지금 시점의 턴 수를 새겨둔다. 이보다 늘어나야 사람이 답한 것으로 인정한다.
  bouncer_state_update "$TASK" --argjson n "$UT_NOW" \
    '.allowed_stop = true | .user_turns_at_wait = (.user_turns_at_wait // $n)'
  # Stop 의 additionalContext 는 턴을 이어가게 만든다. 재진입 때마다 내보내면
  # 사람을 기다리는 동안 hook 이 계속 깨워 Claude Code 상한(9회)까지 돈다.
  # 재진입이면 조용히 멈추게 둔다 — 지시는 첫 Stop 에서 이미 전달됐다.
  [ "$REENTRY" = "true" ] && exit 0
  if [ -n "$INJECT" ] || [ -n "$FAILURES" ]; then
    jq -n --arg c "[$STAGE] 아직 끝나지 않았다.${FAILURES:+$'\n\n'}${FAILURES:+미충족 조건:
}$FAILURES${INJECT:+$'\n\n'}$INJECT" \
      '{hookSpecificOutput:{hookEventName:"Stop", additionalContext:$c}}'
  fi
  exit 0
fi

# 남은 게 done 표시뿐이면 한 번만 막는다. 백그라운드 작업을 기다리며 가벼운
# 도구로 폴링하면 매 Stop 마다 같은 "완료 표시 안 됨" 차단이 반복됐다.
# 스테이지나 남은 조건이 바뀌면 키가 달라져 다시 한 번 막는다.
if [ "$N_FAIL" -gt 0 ] && [ "$N_FAIL" = "$N_PENDING" ] \
   && [ "$HARD_FAIL" != "1" ] && [ "$HUMAN_WAIT" != "1" ]; then
  _pkey="$STAGE:$(printf '%s' "$FAILURES" | cksum | cut -d' ' -f1)"
  if [ "$(bouncer_state "$TASK" '.pending_notice')" = "$_pkey" ]; then
    bouncer_state_update "$TASK" '.continue_streak = 0 | .reentry_count = 0'
    jq -n --arg m "[ai-bouncer] [$STAGE] 완료 표시 대기 중 — 끝났으면 실행: bouncer done '$(printf '%s' "$BLOCKING_IDS" | head -1)'" \
      '{systemMessage:$m}'
    exit 0
  fi
  bouncer_state_update "$TASK" --arg k "$_pkey" '.pending_notice = $k'
fi

# 직전 차단 이후 도구를 하나도 안 썼는데 또 멈추려 한다 = 기다리는 중이다
# (백그라운드 작업 완료 대기 등). 다시 막아봐야 같은 응답만 반복되므로 멈추게 둔다.
# 백그라운드 작업이 끝나면 그 알림으로 턴이 다시 열리고, 그때 다시 판정한다.
SEQ_NOW="$(cat "$TASK/.tool_seq" 2>/dev/null)"; case "$SEQ_NOW" in ''|*[!0-9]*) SEQ_NOW=0 ;; esac
SEQ_AT_BLOCK="$(cat "$TASK/.tool_seq_at_block" 2>/dev/null)"; case "$SEQ_AT_BLOCK" in ''|*[!0-9]*) SEQ_AT_BLOCK=-1 ;; esac
if [ "$REENTRY" = "true" ] && [ "$SEQ_NOW" = "$SEQ_AT_BLOCK" ]; then
  bouncer_state_update "$TASK" '.continue_streak = 0 | .reentry_count = 0'
  jq -n --arg m "[ai-bouncer] [$STAGE] 대기 중 — 미충족 조건이 남아 있어 다음 턴에 이어서 확인한다." \
    '{systemMessage:$m}'
  exit 0
fi

# 재진입 상태에서 상한의 두 배를 넘겼다면 카운터가 어딘가에서 리셋되고 있다는 뜻이다.
# 그 경우 워크플로우 진행보다 세션을 사용자에게 돌려주는 쪽이 안전하다.
REENTRY_N="$(jq -r '.reentry_count // 0' "$TASK/state.json" 2>/dev/null)"
if [ "$REENTRY" = "true" ]; then
  REENTRY_N=$(( REENTRY_N + 1 ))
  bouncer_state_update "$TASK" --argjson n "$REENTRY_N" '.reentry_count = $n'
else
  bouncer_state_update "$TASK" '.reentry_count = 0'; REENTRY_N=0
fi
if [ "$REENTRY_N" -gt $(( MAX_CONTINUE * 2 )) ] 2>/dev/null; then
  bouncer_state_update "$TASK" '.allowed_stop = true | .continue_streak = 0 | .reentry_count = 0'
  jq -n --arg c "${INJECT:+$INJECT$'\n\n'}⛔ [$STAGE] Stop hook 재진입이 비정상적으로 반복됐다 (${REENTRY_N}회).
워크플로우를 더 밀지 않고 세션을 사용자에게 돌려준다.

미충족 조건:
$FAILURES" '{hookSpecificOutput:{hookEventName:"Stop", additionalContext:$c}}'
  exit 0
fi

if [ "$STREAK" -ge "$MAX_CONTINUE" ] 2>/dev/null; then
  bouncer_state_update "$TASK" '.allowed_stop = true | .continue_streak = 0'
  jq -n --arg c "${INJECT:+$INJECT$'\n\n'}⛔ ${MAX_CONTINUE}회 연속 진행했지만 [$STAGE] 단계를 벗어나지 못했다.

미충족 조건:
$FAILURES

AskUserQuestion으로 사용자에게 물어라:
  1. 계속 시도한다
  2. 접근을 바꾼다 (필요하면 이전 단계로 되돌린다)
  3. 이 조건을 이번 작업에서만 건너뛴다:
$(skip_hint)
  4. 작업을 중단한다" '{hookSpecificOutput:{hookEventName:"Stop", additionalContext:$c}}'
  offer_skip
  exit 0
fi

bouncer_state_update "$TASK" '.continue_streak = (.continue_streak // 0) + 1 | .allowed_stop = false'
printf '%s' "$SEQ_NOW" > "$TASK/.tool_seq_at_block" 2>/dev/null || true
guarded_block "[$STAGE] 아직 끝나지 않았다.

미충족 조건:
$FAILURES${INJECT:+$'\n\n'}$INJECT"
