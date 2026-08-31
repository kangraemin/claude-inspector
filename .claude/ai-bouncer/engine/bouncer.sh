#!/usr/bin/env bash
# ai-bouncer CLI — 스킬과 사용자가 쓰는 진입점.
#
#   bouncer scan                      시작 전에 알아야 할 것 전부 (상태 + 모드 + 선택 항목)
#   bouncer start <workflow> <slug> [--parallel] [--off <id> ...]
#   bouncer status                    현재 단계와 남은 조건
#   bouncer run <step-id>             그 step의 명령을 실행하고 결과를 기록
#   bouncer done <step-id>            사람 확인이 필요한 step을 완료 처리
#   bouncer cancel                    작업 취소
#   bouncer check                     workflow.yaml이 유효한지 검사 (아무것도 쓰지 않는다)
#   bouncer worktree finalize         병렬 작업을 base로 FF 머지하고 정리
#
# current_stage / workflow / choices는 이 CLI로 바꿀 수 없다. 전이는 Stop hook만 한다.

set -uo pipefail
_D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_D/lib/common.sh"

PROJECT="${BOUNCER_PROJECT:-$PWD}"
SESSION="${CLAUDE_CODE_SESSION_ID:-}"

die() { printf 'ai-bouncer: %s\n' "$1" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || die "jq가 필요하다. brew install jq"
COMPILED="$(bouncer_compiled_file "$PROJECT")"

need_task() {
  TASK="$(bouncer_my_task "$PROJECT" "$SESSION")" \
    || die "이 세션의 활성 작업이 없다. 'bouncer start <workflow> <slug>'로 시작하라."
  WORK_ROOT="$(bouncer_state "$TASK" '.work_root')"; [ -d "$WORK_ROOT" ] || WORK_ROOT="$PROJECT"
  STAGE="$(bouncer_state "$TASK" '.current_stage')"
}
step_json() { bouncer_stage "$PROJECT" "$2" | jq -c --arg i "$1" '.steps[]? | select(.id == $i)'; }

# ── scan ─────────────────────────────────────────────────────
# 스킬이 제일 먼저, 한 번만 호출한다. 아무것도 만들지 않고 알아야 할 것을 전부 준다.
#   STATE   MINE <dir> <workflow> <stage>  이 세션이 이어서 할 작업
#           OTHER <dir> <stage> <나이>      다른 세션이 잡고 있는 작업
#           NONE                            아무것도 없음
#   WORKFLOW <이름> <label>                 모드 선택지
#   OPTION   <workflow> <stage> <id> <label>  시작할 때 물어볼 선택 항목
cmd_scan() {
  local found=0 d owner stage age wf
  for d in $(bouncer_live_locks "$PROJECT"); do
    owner="$(jq -r '.session_id // empty' "$d/.active" 2>/dev/null)"
    stage="$(bouncer_state "$d" '.current_stage')"
    if [ -n "$SESSION" ] && [ "$owner" = "$SESSION" ]; then
      printf 'STATE\tMINE\t%s\t%s\t%s\n' "$d" "$(bouncer_state "$d" '.workflow')" "$stage"
    else
      age=$(( $(bouncer_lock_age "$d/.active") / 60 ))
      printf 'STATE\tOTHER\t%s\t%s\t%s분 전\n' "$d" "$stage" "$age"
    fi
    found=1
  done
  [ "$found" = 0 ] && printf 'STATE\tNONE\n'

  [ -f "$COMPILED" ] || return 0
  jq -r '.workflows | to_entries[] | "WORKFLOW\t\(.key)\t\(.value.label)"' "$COMPILED"
  while IFS= read -r wf; do
    [ -z "$wf" ] && continue
    while IFS= read -r stage; do
      bouncer_stage "$PROJECT" "$stage" \
        | jq -r --arg w "$wf" --arg s "$stage" \
            '.steps[]? | select(.optional) | "OPTION\t\($w)\t\($s)\t\(.id)\t\(.label)"'
    done < <(bouncer_chain "$PROJECT" "$wf")
  done < <(jq -r '.workflows | keys[]' "$COMPILED")
  return 0
}

# ── check ────────────────────────────────────────────────────
# workflow.yaml을 고친 뒤 검증용. 컴파일만 해보고 결과 파일은 만들지 않는다.
cmd_check() {
  local y; y="$(bouncer_workflow_yaml "$PROJECT")"
  [ -f "$y" ] || die "워크플로우 파일이 없다: $y"
  local err
  if err="$(python3 "$_D/compile.py" "$y" 2>&1 >/dev/null)"; then
    printf 'OK\t%s\n' "$y"
    python3 "$_D/compile.py" "$y" | jq -r '
      "  워크플로우: " + (.workflows | to_entries | map("\(.key) [\(.value.stages | join(" → "))]") | join("\n              "))'
  else
    printf '%s\n' "$err" >&2
    die "workflow.yaml이 유효하지 않다. 고치기 전 상태로 되돌리거나 위 오류를 수정하라."
  fi
}

# ── 시작 ─────────────────────────────────────────────────────
cmd_start() {
  local wf="${1:-}" slug="${2:-}"; shift 2 2>/dev/null || true
  [ -n "$wf" ] && [ -n "$slug" ] || die "usage: bouncer start <workflow> <slug> [--parallel] [--off <id>]"
  [ -n "$SESSION" ] || die "세션 ID를 알 수 없다 (CLAUDE_CODE_SESSION_ID 미설정)."
  [ -f "$COMPILED" ] || die "워크플로우가 컴파일되지 않았다: $COMPILED"

  local first; first="$(bouncer_chain "$PROJECT" "$wf" | head -1)"
  [ -n "$first" ] || die "정의되지 않은 워크플로우: $wf"

  local parallel=0 args=() a
  for a in "$@"; do [ "$a" = "--parallel" ] && parallel=1; done
  for a in "$@"; do [ "$a" = "--parallel" ] || args+=("$a"); done
  set -- ${args[@]+"${args[@]}"}

  # 남의 잠금이 살아 있으면 기본적으로 거부한다. 같은 트리에서 두 작업이 돌면 충돌한다.
  local other conflict=""
  for other in $(bouncer_live_locks "$PROJECT"); do
    [ "$(jq -r '.session_id // empty' "$other/.active" 2>/dev/null)" = "$SESSION" ] && continue
    conflict="$other"
  done
  if [ -n "$conflict" ] && [ "$parallel" = 0 ]; then
    die "다른 세션이 작업 중이다: $conflict ($(bouncer_state "$conflict" '.current_stage'))
같은 트리에서 동시에 진행하면 충돌한다. 둘 중 하나를 골라라:
  - 병렬로 진행 → 'bouncer start $wf \"$slug\" --parallel' (별도 브랜치와 worktree에서 작업한다)
  - 그 작업을 이어서 → 해당 세션에서 계속하라"
  fi

  # optional 기본값: 전부 켜짐. --off 로 끈다.
  # optional 기본값: 전부 켜짐. --off 로 끈다.
  local choices stage
  choices="{}"
  while IFS= read -r stage; do
    while IFS= read -r id; do
      [ -n "$id" ] && choices="$(jq --arg k "$id" '.[$k] = true' <<<"$choices")"
    done < <(bouncer_stage "$PROJECT" "$stage" | jq -r '.steps[]? | select(.optional) | .id')
  done < <(bouncer_chain "$PROJECT" "$wf")
  while [ $# -gt 0 ]; do
    case "$1" in
      --on)  choices="$(jq --arg k "$2" '.[$k] = true'  <<<"$choices")"; shift 2 ;;
      --off) choices="$(jq --arg k "$2" '.[$k] = false' <<<"$choices")"; shift 2 ;;
      *) die "알 수 없는 인자: $1" ;;
    esac
  done

  local slug_safe task_id dir root head_sha base_branch
  slug_safe="$(printf '%s' "$slug" | tr -cs '[:alnum:]-' '-' | sed 's/^-*//;s/-*$//')"
  task_id="$(date +%Y%m%d-%H%M%S)-$slug_safe"
  dir="$(bouncer_tasks_dir "$PROJECT")/$task_id"
  mkdir -p "$dir" || die "태스크 디렉토리 생성 실패: $dir"

  root="$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null)"; [ -n "$root" ] || root="$PROJECT"
  head_sha="$(git -C "$root" rev-parse HEAD 2>/dev/null)"
  base_branch="$(git -C "$root" symbolic-ref --short -q HEAD 2>/dev/null)"

  jq -n --arg id "$task_id" --arg slug "$slug" --arg wf "$wf" --arg stage "$first" \
        --arg sid "$SESSION" --arg root "$root" --arg sha "$head_sha" \
        --arg branch "$base_branch" --arg now "$(date -u +%FT%TZ)" \
        --argjson choices "$choices" '{
      task_id:$id, slug:$slug, workflow:$wf, current_stage:$stage,
      created_at:$now, session_id:$sid,
      repo_root:$root, work_root:$root, worktree:null,
      base_sha:$sha, base_branch:$branch,
      choices:$choices, evidence:{}, shown:{},
      continue_streak:0, allowed_stop:false,
      history:[{stage:$stage, at:$now}]
    }' > "$dir/state.json" || die "state.json 생성 실패"

  jq -n --arg s "$SESSION" --arg now "$(date -u +%FT%TZ)" \
     '{session_id:$s, claimed_at:$now, seen_at:$now}' > "$dir/.active"
  printf 'STARTED\t%s\tworkflow=%s\tstage=%s\n' "$task_id" "$wf" "$first"
  # 병렬이면 곧바로 격리한다. base 브랜치는 이 시점에 확정 기록된다.
  [ "$parallel" = 1 ] && cmd_wt_create "$slug"
  return 0
}

# ── 상태 ─────────────────────────────────────────────────────
cmd_status() {
  need_task
  local wf; wf="$(bouncer_state "$TASK" '.workflow')"
  printf '작업:      %s\n워크플로우: %s\n체인:      %s\n현재 단계:  %s\n작업 위치:  %s\n' \
    "$(bouncer_state "$TASK" '.task_id')" "$wf" \
    "$(bouncer_chain "$PROJECT" "$wf" | tr '\n' ' ')" "$STAGE" "$WORK_ROOT"
  local wt; wt="$(bouncer_state "$TASK" '.worktree.path')"
  [ -n "$wt" ] && printf 'worktree:  %s (base %s)\n' "$wt" "$(bouncer_state "$TASK" '.worktree.base_branch')"

  printf '\n[%s] steps\n' "$STAGE"
  bouncer_stage "$PROJECT" "$STAGE" | jq -r --slurpfile st "$TASK/state.json" '
    .steps[]? |
    (($st[0].evidence[.id] // false) as $done |
     ($st[0].choices[.id]  // true)  as $on |
     "  \(if .optional and ($on|not) then "⃠ (건너뜀)" elif $done then "✅" elif .blocking then "⬜" else "·" end) \(.label)\(if .blocking then "  [\(.blocking)]" else "" end)")'
}

# ── 실행 / 완료 ──────────────────────────────────────────────
cmd_run() {
  need_task
  local id="${1:-}"; [ -n "$id" ] || die "usage: bouncer run <step-id>"
  local step; step="$(step_json "$id" "$STAGE")"
  [ -n "$step" ] || die "현재 단계($STAGE)에 '$id' step이 없다. 'bouncer status'로 확인하라."
  local kind cmd tmo
  kind="$(jq -r '.kind' <<<"$step")"
  [ "$kind" = "run" ] || die "'$id'는 실행 step이 아니다."
  cmd="$(jq -r '.run' <<<"$step")"; tmo="$(jq -r '.timeout' <<<"$step")"

  printf '▶ %s\n  $ %s\n\n' "$(jq -r '.label' <<<"$step")" "$cmd"
  local rc=0
  if command -v timeout >/dev/null 2>&1; then
    ( cd "$WORK_ROOT" && timeout "$tmo" bash -lc "$cmd" ) || rc=$?
  else
    ( cd "$WORK_ROOT" && bash -lc "$cmd" ) || rc=$?
  fi

  if [ "$rc" -eq 0 ]; then
    bouncer_state_update "$TASK" --arg k "$id" '.evidence[$k] = true'
    printf '\n✅ 통과 — %s\n' "$id"
  else
    bouncer_state_update "$TASK" --arg k "$id" '.evidence[$k] = false
      | .attempts[$k] = ((.attempts[$k] // 0) + 1)'
    printf '\n❌ 실패 (exit %s) — %s\n출력을 읽고 고친 뒤 다시 실행하라.\n' "$rc" "$id"
    return 1
  fi
}

cmd_done() {
  need_task
  local id="${1:-}"; [ -n "$id" ] || die "usage: bouncer done <step-id>"
  local step; step="$(step_json "$id" "$STAGE")"
  [ -n "$step" ] || die "현재 단계($STAGE)에 '$id' step이 없다."
  local kind blocking
  kind="$(jq -r '.kind' <<<"$step")"; blocking="$(jq -r '.blocking // empty' <<<"$step")"
  [ "$kind" = "run" ] && die "'$id'는 실행 step이다. 'bouncer run $id'를 써라 — 결과는 엔진이 판정한다."
  case "$blocking" in
    plan_approved) die "'$id'는 plan mode 승인으로만 통과한다. ExitPlanMode를 호출하라." ;;
    skill:*)       die "'$id'는 '${blocking#skill:}' 스킬을 실제로 실행해야 통과한다." ;;
    "")            die "'$id'는 blocking이 아니다. 완료 처리할 필요가 없다." ;;
  esac
  bouncer_state_update "$TASK" --arg k "$id" '.evidence[$k] = true'
  printf 'DONE\t%s\n' "$id"
}

cmd_cancel() {
  need_task
  bouncer_state_update "$TASK" --arg n "$(date -u +%FT%TZ)" '.current_stage = "cancelled" | .cancelled_at = $n'
  rm -f "$TASK/.active"
  printf 'CANCELLED\t%s\n' "$TASK"
}

# ── worktree ─────────────────────────────────────────────────
cmd_wt_create() {
  need_task
  local root slug base_branch base_sha detached=false repo branch wt
  root="$(bouncer_state "$TASK" '.repo_root')"
  git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || die "git 레포가 아니다: $root"
  slug="${1:-$(bouncer_state "$TASK" '.slug')}"

  # base는 지금 확정해서 기록한다. 나중에 역추론하지 않는다.
  base_branch="$(git -C "$root" symbolic-ref --short -q HEAD 2>/dev/null)"
  base_sha="$(git -C "$root" rev-parse HEAD 2>/dev/null)"
  [ -n "$base_sha" ] || die "HEAD를 읽을 수 없다 (커밋이 없는 레포?)"
  [ -n "$base_branch" ] || { detached=true; base_branch="$base_sha"; }

  repo="$(basename "$root")"
  branch="bouncer/$(printf '%s' "$slug" | tr -cs '[:alnum:]-' '-' | sed 's/^-*//;s/-*$//')-$(date +%H%M%S)"
  wt="$HOME/.ai-bouncer/worktrees/$repo/${branch//\//-}"
  mkdir -p "$(dirname "$wt")" || die "worktree 상위 디렉토리 생성 실패"
  git -C "$root" worktree add -b "$branch" "$wt" "$base_sha" >/dev/null 2>&1 || die "worktree 생성 실패: $wt"

  bouncer_state_update "$TASK" --arg p "$wt" --arg b "$branch" --arg bb "$base_branch" \
    --arg bs "$base_sha" --argjson det "$detached" \
    '.worktree = {path:$p, branch:$b, base_branch:$bb, base_sha:$bs, detached:$det}
     | .work_root = $p | .base_sha = $bs'
  printf 'WORKTREE\t%s\tbranch=%s\tbase=%s%s\n' "$wt" "$branch" "$base_branch" \
    "$([ "$detached" = true ] && printf ' (detached — FF 머지 대상 없음)')"
}

cmd_wt_finalize() {
  need_task
  local wt branch base root detached cur dirty
  wt="$(bouncer_state "$TASK" '.worktree.path')"; [ -n "$wt" ] || die "이 작업은 worktree를 쓰지 않는다."
  branch="$(bouncer_state "$TASK" '.worktree.branch')"
  base="$(bouncer_state "$TASK" '.worktree.base_branch')"
  detached="$(bouncer_state "$TASK" '.worktree.detached')"
  root="$(bouncer_state "$TASK" '.repo_root')"

  dirty="$(git -C "$wt" status --porcelain 2>/dev/null)"
  [ -z "$dirty" ] || die "worktree에 커밋되지 않은 변경이 있다. 먼저 커밋하라:
$dirty"
  [ "$detached" = "true" ] && die "base가 detached HEAD($base)라 FF 머지할 수 없다. worktree는 보존된다: $wt"
  git -C "$root" show-ref --verify --quiet "refs/heads/$base" \
    || die "base 브랜치 '$base'가 사라졌다. worktree는 보존된다: $wt"

  if ! git -C "$wt" rebase "$base" >/dev/null 2>&1; then
    git -C "$wt" rebase --abort >/dev/null 2>&1
    die "base($base)와 충돌해 rebase 실패. worktree에서 수동 해결 후 재시도: $wt"
  fi
  cur="$(git -C "$root" symbolic-ref --short -q HEAD 2>/dev/null)"
  [ "$cur" = "$base" ] || die "메인 레포가 '$base'가 아니라 '$cur'에 있다.
'git -C $root switch $base' 후 재시도하라. worktree는 보존된다."
  git -C "$root" merge --ff-only "$branch" >/dev/null 2>&1 \
    || die "FF 머지 실패 ($base <- $branch). worktree는 보존된다: $wt"

  git -C "$root" worktree remove "$wt" --force >/dev/null 2>&1
  git -C "$root" branch -d "$branch" >/dev/null 2>&1
  bouncer_state_update "$TASK" '.worktree.merged = true | .work_root = .repo_root'
  printf 'MERGED\t%s -> %s\n' "$branch" "$base"
}

case "${1:-}" in
  scan)      shift; cmd_scan "$@" ;;
  check)     shift; cmd_check "$@" ;;
  start)     shift; cmd_start "$@" ;;
  status)    shift; cmd_status "$@" ;;
  run)       shift; cmd_run "$@" ;;
  done)      shift; cmd_done "$@" ;;
  cancel)    shift; cmd_cancel "$@" ;;
  worktree)  shift
             case "${1:-}" in
               finalize) shift; cmd_wt_finalize "$@" ;;
               create)   die "worktree는 'bouncer start <workflow> <slug> --parallel' 로 만든다." ;;
               *) die "usage: bouncer worktree finalize" ;;
             esac ;;
  ""|-h|--help) sed -n '3,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
  *) die "알 수 없는 명령: $1" ;;
esac
