#!/usr/bin/env bash
# ai-bouncer CLI — 스킬과 사용자가 쓰는 진입점.
#
#   bouncer scan                      시작 전에 알아야 할 것 전부 (상태 + 모드 + 선택 항목)
#   bouncer start <workflow> <slug> [--parallel] [--off <id> ...]
#   bouncer status                    현재 단계와 남은 조건
#   bouncer run <step-id>             그 step의 명령을 실행하고 결과를 기록
#   bouncer done <step-id>            사람 확인이 필요한 step을 완료 처리
#   bouncer cancel                    작업 취소
#   bouncer todo [add|done <n>|drop <n>]  할 일 목록 (checklist 게이트가 이걸 센다)
#   bouncer skip <step-id>            엔진이 포기한 조건을 이번 작업에서만 건너뛴다
#   bouncer release [--force]         죽은 세션이 남긴 잠금 확인 / 회수
#   bouncer resume [task-id]          회수된 작업을 이 세션이 다시 잡는다
#   bouncer workflows                 정의된 모드 목록
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

# need_task [--mutating]
# 사람이 자기 터미널에서 칠 때는 세션 ID가 없다. 진행 중 작업이 하나뿐이면
# 그걸 **보여주는** 것까지는 해준다 — 안 그러면 README가 권하는 status가 안 먹힌다.
# 다만 바꾸는 명령(cancel/done/skip/run/worktree)은 열어주지 않는다:
# 그 작업은 지금 다른 세션이 쥐고 있는 것이고, 말없이 취소하면 그 세션은
# 알림 한 줄 없이 게이트를 잃는다 (감사에서 실제로 재현됐다).
need_task() {
  local mutating=0
  [ "${1:-}" = "--mutating" ] && mutating=1
  TASK="$(bouncer_my_task "$PROJECT" "$SESSION")" || TASK=""
  if [ -z "$TASK" ] && [ -z "$SESSION" ]; then
    local live; live="$(bouncer_live_locks "$PROJECT")"
    if [ "$(printf '%s\n' "$live" | grep -c .)" = 1 ]; then
      if [ "$mutating" = 1 ]; then
        die "진행 중인 작업이 있지만 이 세션 것이 아니다: $(basename "$live")
그 작업을 쥐고 있는 세션에서 끝내야 한다.
그 세션이 죽은 게 확실하면: bouncer release --force"
      fi
      TASK="$live"
      printf '(세션 ID가 없어 진행 중인 작업 하나를 대상으로 한다: %s)\n' \
        "$(basename "$TASK")" >&2
    fi
  fi
  [ -n "$TASK" ] \
    || die "이 세션의 활성 작업이 없다.
진행 중인 작업을 보려면: bouncer release   (누가 잡고 있는지 나온다)
새로 시작하려면:        bouncer start <workflow> <slug>"
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
  # release로 회수됐거나 세션이 죽은 뒤 남은 미완 작업. 안 보여주면
  # 모델은 "없다"고 판단해 새 작업을 시작하고, 하던 작업은 영영 묻힌다.
  local tasks; tasks="$(bouncer_tasks_dir "$PROJECT")"
  if [ -d "$tasks" ]; then
    for d in "$tasks"/*/; do
      [ -f "${d}state.json" ] || continue
      [ -f "${d}.active" ] && continue
      if ! jq -e . "${d}state.json" >/dev/null 2>&1; then
        printf 'ORPHAN\t%s\t(상태 파일 손상 — 이어받을 수 없다)\n' "$(basename "${d%/}")"
        found=2; continue
      fi
      st="$(bouncer_state "${d%/}" '.current_stage')"
      [ "$st" = cancelled ] && continue
      [ -n "$(bouncer_state "${d%/}" '.finished_at')" ] && continue
      printf 'ORPHAN\t%s\t%s\t%s\n' "$(basename "${d%/}")" \
        "$(bouncer_state "${d%/}" '.workflow')" "$st"
      found=2
    done
  fi
  [ "$found" = 0 ] && printf 'STATE\tNONE\n'

  [ -f "$COMPILED" ] || return 0
  if ! jq -e . "$COMPILED" >/dev/null 2>&1; then
    printf 'ERROR\t컴파일 결과가 손상됐다: %s\n' "$COMPILED"
    printf 'ERROR\t`bouncer check` 로 workflow.yaml을 확인하라. 다음 세션 시작 때 다시 컴파일된다.\n'
    return 0
  fi
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

# ── workflows ────────────────────────────────────────────────
# 모드 선택지만 뽑는다. scan은 상태까지 같이 주므로 사람이 읽기엔 이쪽이 낫다.
cmd_workflows() {
  [ -f "$COMPILED" ] || die "워크플로우가 컴파일되지 않았다: $COMPILED"
  jq -e . "$COMPILED" >/dev/null 2>&1 \
    || die "컴파일 결과가 손상됐다: $COMPILED
'bouncer check' 로 workflow.yaml을 확인하라. 다음 세션 시작 때 다시 컴파일된다."
  jq -r '.workflows | to_entries[] |
    "\(.key)\t\(.value.label)\n    " + (.value.stages | join(" → "))' "$COMPILED"
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
  jq -e . "$COMPILED" >/dev/null 2>&1 \
    || die "컴파일 결과가 손상됐다: $COMPILED
'bouncer check' 로 workflow.yaml을 확인하라. 다음 세션 시작 때 다시 컴파일된다."

  local first; first="$(bouncer_chain "$PROJECT" "$wf" | head -1)"
  [ -n "$first" ] || die "정의되지 않은 워크플로우: $wf"

  local parallel=0 args=() a
  for a in "$@"; do [ "$a" = "--parallel" ] && parallel=1; done
  for a in "$@"; do [ "$a" = "--parallel" ] || args+=("$a"); done
  set -- ${args[@]+"${args[@]}"}

  # 남의 잠금이 살아 있으면 기본적으로 거부한다. 같은 트리에서 두 작업이 돌면 충돌한다.
  local other conflict="" mine=""
  for other in $(bouncer_live_locks "$PROJECT"); do
    if [ "$(jq -r '.session_id // empty' "$other/.active" 2>/dev/null)" = "$SESSION" ]; then
      mine="$other"; continue
    fi
    conflict="$other"
  done
  # 한 세션이 활성 작업을 둘 이상 가지면, 두 번째는 hook에 잡히지 않고 락만 붙든다.
  [ -n "$mine" ] && die "이 세션에 이미 진행 중인 작업이 있다: $mine
'bouncer status' 로 확인하고 이어서 하거나, 'bouncer cancel' 로 정리한 뒤 새로 시작하라."

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
      --off)
        # 없는 id를 조용히 받으면 사용자는 껐다고 믿는데 게이트는 살아 있다.
        jq -e --arg k "$2" 'has($k)' <<<"$choices" >/dev/null 2>&1 \
          || die "선택 항목이 아니다: $2
이 워크플로우의 선택 항목:
$(jq -r 'keys[] | "  " + .' <<<"$choices")"
        choices="$(jq --arg k "$2" '.[$k] = false' <<<"$choices")"; shift 2 ;;
      *) die "알 수 없는 인자: $1" ;;
    esac
  done

  local slug_safe task_id dir root head_sha base_branch sid_tag
  slug_safe="$(printf '%s' "$slug" | tr -cs '[:alnum:]-' '-' | sed 's/^-*//;s/-*$//')"
  # 같은 초에 같은 slug로 두 세션이 시작하면 디렉토리가 겹쳐 한쪽이 태스크를 잃는다.
  # 세션 성분을 넣어 충돌 자체를 없앤다.
  sid_tag="$(printf '%s' "$SESSION" | shasum -a 256 | cut -c1-6)"
  task_id="$(date +%Y%m%d-%H%M%S)-$sid_tag-$slug_safe"
  dir="$(bouncer_tasks_dir "$PROJECT")/$task_id"
  mkdir -p "$(dirname "$dir")" || die "태스크 디렉토리 생성 실패: $dir"
  # -p 를 쓰면 이미 있어도 성공한다. 겹치면 실패해야 남의 것을 덮어쓰지 않는다.
  mkdir "$dir" 2>/dev/null || die "태스크 디렉토리가 이미 있다: $dir"

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

  # 검사와 생성 사이에 다른 세션이 끼어들 수 있다(TOCTOU).
  # 내 락을 만든 뒤 다시 확인해서, 나보다 먼저 잡은 쪽이 있으면 내 것을 물린다.
  if [ "$parallel" = 0 ]; then
    local mine_at other_at lose
    mine_at="$(jq -r '.claimed_at' "$dir/.active")"
    for other in $(bouncer_live_locks "$PROJECT"); do
      [ "$other" = "$dir" ] && continue
      [ "$(jq -r '.session_id // empty' "$other/.active" 2>/dev/null)" = "$SESSION" ] && continue
      other_at="$(jq -r '.claimed_at // empty' "$other/.active" 2>/dev/null)"
      [ -n "$other_at" ] || continue
      # claimed_at 은 초 단위라 같은 초에 시작하면 문자열이 같다.
      # 그때 양쪽이 "상대가 먼저"라고 판단해 둘 다 물러나면 아무도 시작하지 못한다.
      # 동률이면 task_id 사전순으로 승자를 하나 정한다.
      lose=0
      if [ "$other_at" \< "$mine_at" ]; then lose=1
      elif [ "$other_at" = "$mine_at" ] && [ "$(basename "$other")" \< "$(basename "$dir")" ]; then lose=1
      fi
      if [ "$lose" = 1 ]; then
        rm -rf "$dir"
        die "다른 세션이 먼저 작업을 시작했다: $other
같은 트리에서 동시에 진행하면 충돌한다.
  - 병렬로 진행 → 'bouncer start $wf \"$slug\" --parallel'
  - 그 작업을 이어서 → 해당 세션에서 계속하라"
      fi
    done
  fi
  # 병렬이면 곧바로 격리한다. base 브랜치는 이 시점에 확정 기록된다.
  # 격리에 실패했는데 태스크를 남기면, 사용자가 요청한 격리 없이 메인 트리에서
  # 락을 쥔 채 작업하게 된다 — 그 상태로 두느니 시작을 무르는 게 맞다.
  # STARTED 는 격리까지 성공한 뒤에 찍는다. 먼저 찍으면 롤백돼도
  # "시작됐다"가 화면에 남아 무엇이 참인지 알 수 없다.
  if [ "$parallel" = 1 ]; then
    # cmd_wt_create 내부는 die(=exit)를 쓴다. 서브셸로 감싸야 여기로 돌아온다.
    # 그러지 않으면 아래 롤백은 영원히 실행되지 않는 죽은 코드다.
    if ! ( cmd_wt_create "$slug" ); then
      rm -rf "$dir"
      die "격리(worktree) 생성에 실패해 작업을 시작하지 않았다. 위 오류를 해결하고 다시 시도하라."
    fi
  fi
  printf 'STARTED\t%s\tworkflow=%s\tstage=%s\n' "$task_id" "$wf" "$first"

  # 첫 스테이지 지시를 바로 돌려준다. Stop을 기다리면 첫 응답이 지시 없이 나간다.
  local txt
  txt="$(bouncer_stage "$PROJECT" "$first" | jq -r '[.steps[]? | select(.kind=="inject") | .text] | join("\n\n")')"
  if [ -n "$txt" ]; then
    printf '\n%s\n' "$txt"
    while IFS= read -r id; do
      [ -n "$id" ] && bouncer_state_update "$dir" --arg k "$id" '.shown[$k] = true'
    done < <(bouncer_stage "$PROJECT" "$first" | jq -r '.steps[]? | select(.kind=="inject") | .id')
  fi
  return 0
}

# ── 상태 ─────────────────────────────────────────────────────
cmd_status() {
  need_task
  # 빈 필드를 늘어놓고 rc=0으로 끝내면 사용자는 정상인 줄 안다.
  jq -e . "$TASK/state.json" >/dev/null 2>&1 \
    || die "state.json이 손상됐다: $TASK/state.json
hook은 이 상태에서 작업을 진행시키지 않는다.
  · 작업을 포기한다: bouncer cancel
  · 잠금만 푼다:     bouncer release --force"
  local wf; wf="$(bouncer_state "$TASK" '.workflow')"
  jq -e . "$COMPILED" >/dev/null 2>&1 \
    || die "컴파일 결과가 손상됐다: $COMPILED
'bouncer check' 로 workflow.yaml을 확인하라. 다음 세션 시작 때 다시 컴파일된다."
  [ -n "$(bouncer_chain "$PROJECT" "$wf")" ] \
    || die "워크플로우 '$wf' 가 workflow.yaml에 없다 (작업 도중 삭제·개명된 것으로 보인다).
되돌리거나 'bouncer cancel' 로 정리하라."
  [ -n "$(bouncer_stage "$PROJECT" "$STAGE")" ] \
    || die "단계 '$STAGE' 가 workflow.yaml에 없다 (작업 도중 삭제·개명된 것으로 보인다).
되돌리거나 'bouncer cancel' 로 정리하라."
  printf '작업:      %s\n워크플로우: %s\n체인:      %s\n현재 단계:  %s\n작업 위치:  %s\n' \
    "$(bouncer_state "$TASK" '.task_id')" "$wf" \
    "$(bouncer_chain "$PROJECT" "$wf" | tr '\n' ' ')" "$STAGE" "$WORK_ROOT"
  local wt; wt="$(bouncer_state "$TASK" '.worktree.path')"
  [ -n "$wt" ] && printf 'worktree:  %s (base %s)\n' "$wt" "$(bouncer_state "$TASK" '.worktree.base_branch')"

  # 할 일 목록이 있으면 함께 보여준다 — checklist 게이트가 이걸 센다
  if [ "$(jq -r '(.checklist // []) | length' "$TASK/state.json" 2>/dev/null)" != 0 ]; then
    printf '\n할 일\n'
    jq -r '(.checklist // []) | to_entries[] |
      "  \(.key + 1). \(if .value.done then "✅" else "⬜" end) \(.value.text)"' "$TASK/state.json"
  fi

  printf '\n[%s] steps\n' "$STAGE"
  bouncer_stage "$PROJECT" "$STAGE" | jq -r --slurpfile st "$TASK/state.json" '
    .steps[]? | .id as $sid |
    (($st[0].evidence[$sid] // false) as $done |
     (if ($st[0].skipped[$sid] // false) then false
      elif ($st[0].choices | has($sid)) then $st[0].choices[$sid]
      else true end) as $on |
     ($st[0].skipped[$sid] // false) as $skip |
     "  \(if $skip then "⃠" elif ($on|not) then "⃠" elif $done then "✅" elif .blocking then "⬜" else "·" end) \(.label)\(if $skip then "  (건너뜀)" elif ($on|not) then "  (이번 작업에서 끔)" elif .blocking then "  [\(.blocking)]" else "" end)\n      id: \($sid)")'
}

# ── 실행 / 완료 ──────────────────────────────────────────────
cmd_run() {
  need_task --mutating
  local id="${1:-}"; [ -n "$id" ] || die "usage: bouncer run <step-id>"
  local step; step="$(step_json "$id" "$STAGE")"
  [ -n "$step" ] || die "현재 단계($STAGE)에 '$id' step이 없다. 'bouncer status'로 확인하라."
  local kind cmd tmo
  # jq의 `//` 는 false를 "없음"으로 보므로 has()로 물어야 한다.
  if [ "$(jq -r '.optional' <<<"$step")" = "true" ] \
     && [ "$(jq -r --arg k "$id" 'if (.choices | has($k)) then .choices[$k] else true end' \
              "$TASK/state.json")" = "false" ]; then
    die "'$id'는 이번 작업에서 끈 항목이다. 실행할 필요가 없다."
  fi
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
  need_task --mutating
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
  need_task --mutating
  local noted=1
  bouncer_state_update "$TASK" --arg n "$(date -u +%FT%TZ)" \
    '.current_stage = "cancelled" | .cancelled_at = $n' || noted=0
  rm -f "$TASK/.active"
  local wt br
  wt="$(bouncer_state "$TASK" '.worktree.path')"
  br="$(bouncer_state "$TASK" '.worktree.branch')"
  if [ -n "$wt" ] && [ "$(bouncer_state "$TASK" '.worktree.merged')" != true ]; then
    printf '⚠️ 병렬 작업의 worktree와 브랜치는 남는다 (커밋이 있을 수 있다):\n' >&2
    printf '   worktree: %s\n   브랜치:   %s\n' "$wt" "$br" >&2
    printf '   버리려면: git worktree remove --force %s && git branch -D %s\n' "$wt" "$br" >&2
  fi
  if [ "$noted" = 1 ]; then
    printf 'CANCELLED\t%s\n' "$TASK"
  else
    printf 'CANCELLED\t%s\n' "$TASK"
    printf '⚠️ state.json 이 손상돼 취소 표시를 남기지 못했다. 잠금은 해제했다.\n' >&2
  fi
}

# ── release ──────────────────────────────────────────────────
# 세션이 크래시하면 SessionEnd가 안 돌아 .active가 남는다. stale_lock_hours(기본 12시간)
# 전에는 아무도 시작할 수 없었고, cancel은 자기 작업만 다뤄서 탈출구가 없었다.
# 남의 작업을 건드리는 일이라 --force를 반드시 요구한다.
cmd_release() {
  local force=0 d owner age found=0
  case "${1:-}" in
    --force) force=1 ;;
    "") ;;
    *) die "알 수 없는 인자: $1
usage: bouncer release [--force]" ;;
  esac
  [ $# -gt 1 ] && die "인자가 너무 많다. usage: bouncer release [--force]"
  for d in $(bouncer_live_locks "$PROJECT"); do
    found=1
    owner="$(jq -r '.session_id // "?"' "$d/.active" 2>/dev/null)"
    age=$(( $(bouncer_lock_age "$d/.active") / 60 ))
    if [ "$owner" = "$SESSION" ] && [ "$force" = 0 ]; then
      printf '  (내 작업) %s — %s\n' "$(bouncer_state "$d" '.current_stage')" "$d"
      printf '     이 세션 것이다. 끝내려면: bouncer cancel\n'
      continue
    fi
    if [ "$force" = 0 ]; then
      printf '  세션 %s · 단계 %s · %s분 전 · %s\n' \
        "$owner" "$(bouncer_state "$d" '.current_stage')" "$age" "$d"
      continue
    fi
    rm -f "$d/.active" && printf 'RELEASED\t%s\n' "$d"
  done
  [ "$found" = 0 ] && { printf '잠긴 작업이 없다.\n'; return 0; }
  if [ "$force" = 0 ]; then
    printf '\n다른 세션이 살아 있다면 그 세션에서 계속하는 게 맞다.\n'
    printf '그 세션이 죽은 게 확실하면: bouncer release --force\n'
    printf '작업 기록은 남는다. 회수한 뒤 이어서 하려면: bouncer resume <task-id>\n'
  fi
}

# ── resume ───────────────────────────────────────────────────
# release로 잠금을 푼 작업은 아무도 못 잡는 상태가 된다 (.active가 없으면
# my_task가 못 찾고, status/scan에서도 사라진다). 다시 잡는 길을 열어둔다.
cmd_resume() {
  [ $# -gt 1 ] && die "인자가 너무 많다. usage: bouncer resume [task-id]"
  local want="${1:-}"
  # 인자 없는 호출은 목록만 보여주는 조회다 — 세션 ID 없이도 된다.
  # (release 가 이걸 안내하는데 한 줄 에러로 죽어서 탈출구가 끊겼다)
  [ -n "$want" ] && [ -z "$SESSION" ] \
    && die "이어받으려면 세션 ID가 필요하다 (CLAUDE_CODE_SESSION_ID 미설정).
목록만 보려면 인자 없이: bouncer resume"
  local tasks d found=""
  tasks="$(bouncer_tasks_dir "$PROJECT")"
  [ -d "$tasks" ] || die "이 프로젝트에 작업 기록이 없다."
  if [ -z "$want" ]; then
    printf '이어서 할 작업을 고르라: bouncer resume <task-id>\n\n'
    local n=0 st
    for d in "$tasks"/*/; do
      [ -f "$d/state.json" ] || continue
      [ -f "$d/.active" ] && continue
      jq -e . "${d}state.json" >/dev/null 2>&1 || continue   # 손상된 것은 못 이어받는다
      st="$(bouncer_state "${d%/}" '.current_stage')"
      # 끝났거나 취소된 것은 이어받을 게 없다
      [ "$st" = cancelled ] && continue
      [ -n "$(bouncer_state "${d%/}" '.finished_at')" ] && continue
      n=$((n+1))
      printf '  %-42s %s / %s\n' "$(basename "$d")" \
        "$(bouncer_state "${d%/}" '.workflow')" "$st"
    done
    [ "$n" = 0 ] && printf '  (이어받을 작업이 없다)\n'
    return 0
  fi
  # start 와 같은 불변식을 지켜야 한다. 두 개를 잡으면 hook은 하나만 진행시키고
  # 나머지는 게이트 없이 락만 붙든 채 남는다.
  local mine; mine="$(bouncer_my_task "$PROJECT" "$SESSION" 2>/dev/null || true)"
  [ -n "$mine" ] && die "이미 진행 중인 작업이 있다: $(basename "$mine")
먼저 끝내거나 'bouncer cancel' 로 정리한 뒤에 이어받아라."
  d="$tasks/$want"
  [ -d "$d" ] || die "그런 작업이 없다: $want"
  [ -f "$d/.active" ] && die "이미 누군가 잡고 있다. 먼저 'bouncer release' 로 확인하라."
  jq -e . "$d/state.json" >/dev/null 2>&1 \
    || die "그 작업의 상태 파일이 손상됐다: $want
이어받아도 진행할 수 없다. 정리하려면 그 디렉토리를 지워라:
  rm -rf $d"
  [ "$(bouncer_state "$d" '.current_stage')" = cancelled ] && die "취소된 작업이다."
  jq -n --arg s "$SESSION" --arg t "$(date -u +%FT%TZ)" \
    '{session_id:$s, claimed_at:$t}' > "$d/.active" || die "잠금을 만들지 못했다."
  printf 'RESUMED\t%s\tstage=%s\n' "$want" "$(bouncer_state "$d" '.current_stage')"
}

# ── skip ─────────────────────────────────────────────────────
# 엔진이 포기 메시지에서 "이 조건을 이번 작업에서만 건너뛴다"를 제안하는데
# 정작 그런 명령이 없었다. 엔진이 이미 포기한(max_attempts 소진) step만 열어준다 —
# 그래야 게이트를 처음부터 우회하는 수단이 되지 않는다.
cmd_skip() {
  need_task --mutating
  local id="${1:-}"; [ -n "$id" ] || die "usage: bouncer skip <step-id>"
  # 막고 있는 게이트가 현재 스테이지 소속이 아닐 수 있다 (반송된 뒤가 그렇다).
  # 그래서 현재 스테이지가 아니라 이 워크플로우의 체인 전체에서 찾는다.
  local wf owner="" st
  wf="$(bouncer_state "$TASK" '.workflow')"
  while IFS= read -r st; do
    [ -z "$st" ] && continue
    if [ -n "$(step_json "$id" "$st")" ]; then owner="$st"; break; fi
  done < <(bouncer_chain "$PROJECT" "$wf")
  [ -n "$owner" ] || die "'$id' 라는 step이 이 워크플로우($wf)에 없다.
'bouncer status'로 현재 단계의 step id를 확인하라."
  # 엔진이 포기하며 **그 id 를 직접 제안했을 때만** 열어준다.
  # 스테이지 단위로 열면 제안하지 않은 게이트까지 같이 열린다.
  jq -e --arg k "$id" '(.skip_allowed // []) | index($k)' "$TASK/state.json" >/dev/null 2>&1 \
    || die "'$id' 는 엔진이 건너뛰라고 제안한 조건이 아니다.
건너뛰기는 엔진이 '이 조건을 이번 작업에서만 건너뛴다'와 함께 그 명령을
찍어줬을 때만 쓸 수 있다. 지금은 조건을 충족시켜라 — 'bouncer status' 참고."
  # 제안을 소모한다. 같은 제안을 두 번 쓰지는 못한다.
  bouncer_state_update "$TASK" --arg k "$id" \
    '.skipped[$k] = true
     | .skip_allowed = ((.skip_allowed // []) | map(select(. != $k)))' \
    || die "state.json을 갱신하지 못했다."
  printf 'SKIPPED\t%s\t(%s)\n' "$id" "$owner"
  printf '이번 작업에서만 건너뛴다. workflow.yaml은 그대로다.\n'
}

# ── todo ─────────────────────────────────────────────────────
# 할 일 목록. `blocking: checklist` 는 이 목록을 **엔진이 세서** 판정한다.
# 목록을 모델이 쓰지만, 한 번 적은 항목은 조용히 사라지지 않는다 —
# 지우면 기록에 남고, 세우자마자 같은 턴에 전부 체크할 수도 없다.
cmd_todo() {
  need_task
  local sub="${1:-list}"; shift 2>/dev/null || true
  # 필드가 없으면 bouncer_state 가 빈 값을 준다 — --argjson 이 깨진다.
  local UT; UT="$(jq -r '.user_turns // 0' "$TASK/state.json" 2>/dev/null)"
  [ "$UT" -eq "$UT" ] 2>/dev/null || UT=0
  case "$sub" in
    list|"")
      local n
      n="$(jq -r '(.checklist // []) | length' "$TASK/state.json")"
      if [ "$n" = 0 ]; then
        printf '할 일 목록이 비어 있다. 요청받은 항목을 적어라:\n'
        printf "  bouncer todo add '항목'\n"
        return 0
      fi
      jq -r '(.checklist // []) | to_entries[] |
        "  \(.key + 1). \(if .value.done then "✅" else "⬜" end) \(.value.text)"' \
        "$TASK/state.json"
      printf '\n남은 항목: %s / %s\n' \
        "$(jq -r '[(.checklist // [])[] | select(.done | not)] | length' "$TASK/state.json")" "$n"
      local dropped
      dropped="$(jq -r '(.dropped // []) | length' "$TASK/state.json")"
      [ "$dropped" != 0 ] && printf '뺀 항목 %s개 (bouncer todo dropped 로 확인)\n' "$dropped"
      return 0 ;;
    add)
      [ $# -gt 0 ] || die "usage: bouncer todo add '<항목>' ['<항목>' …]"
      local t
      for t in "$@"; do
        [ -n "$t" ] || continue
        bouncer_state_update "$TASK" --arg t "$t" --argjson u "$UT" \
          '.checklist = ((.checklist // []) + [{text:$t, done:false}]) | .checklist_turn = $u' \
          || die "목록을 갱신하지 못했다."
      done
      cmd_todo list ;;
    done)
      local i="${1:-}"
      [ -n "$i" ] || die "usage: bouncer todo done <번호>"
      [ "$i" -eq "$i" ] 2>/dev/null || die "번호를 숫자로 줘라: $i"
      jq -e --argjson i "$((i-1))" '(.checklist // []) | length > $i' "$TASK/state.json" >/dev/null 2>&1 \
        || die "그런 항목이 없다: $i  ('bouncer todo' 로 번호 확인)"
      bouncer_state_update "$TASK" --argjson i "$((i-1))" --arg t "$(date -u +%FT%TZ)" \
        '.checklist[$i].done = true | .checklist[$i].at = $t' || die "갱신 실패."
      cmd_todo list ;;
    drop)
      local i="${1:-}"
      [ -n "$i" ] || die "usage: bouncer todo drop <번호>"
      [ "$i" -eq "$i" ] 2>/dev/null || die "번호를 숫자로 줘라: $i"
      jq -e --argjson i "$((i-1))" '(.checklist // []) | length > $i' "$TASK/state.json" >/dev/null 2>&1 \
        || die "그런 항목이 없다: $i"
      # 지운 항목은 기록에 남긴다. 조용히 사라지면 목록이 게이트 역할을 못 한다.
      bouncer_state_update "$TASK" --argjson i "$((i-1))" --arg t "$(date -u +%FT%TZ)" \
        --argjson u "$UT" \
        '.dropped = ((.dropped // []) + [(.checklist[$i] + {dropped_at:$t})])
         | .checklist = (.checklist | del(.[$i]))
         | .checklist_turn = $u' || die "갱신 실패."
      printf '뺐다. 사용자에게 왜 뺐는지 알려라.\n'
      cmd_todo list ;;
    dropped)
      jq -r '(.dropped // [])[] | "  ⃠ \(.text)"' "$TASK/state.json" ;;
    *) die "usage: bouncer todo [list|add|done <n>|drop <n>|dropped]" ;;
  esac
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
  # 이 안내가 없으면 세션은 메인 레포에 그대로 남아 편집하고, 게이트는
  # 손대지 않은 worktree를 보고 전부 통과한다. 실제로 그렇게 깨졌었다.
  printf '\n⚠️ 지금부터 모든 작업은 이 worktree 안에서 한다. 먼저 이동해라:\n    cd %s\n' "$wt"
  printf '메인 레포에서 파일을 고치면 hook이 막는다 (검증이 다른 트리를 보게 되므로).\n'
}

cmd_wt_finalize() {
  need_task --mutating
  local _wt; _wt="$(bouncer_state "$TASK" '.worktree.path')"
  [ -n "$_wt" ] || die "이 작업은 병렬(worktree) 작업이 아니다."
  # 없는 디렉토리에 git 을 돌리면 빈 출력이 나와 "깨끗함"으로 통과하고,
  # 뒤이은 rebase 실패가 "충돌"로 오진된다.
  [ -d "$_wt" ] || die "worktree 디렉토리가 없다: $_wt
되살리거나 작업을 포기해야 한다:
  git worktree prune && git worktree add $_wt $(bouncer_state "$TASK" '.worktree.branch')
  bouncer cancel"
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
  workflows) shift; cmd_workflows "$@" ;;
  release)   shift; cmd_release "$@" ;;
  skip)      shift; cmd_skip "$@" ;;
  todo)      shift; cmd_todo "$@" ;;
  resume)    shift; cmd_resume "$@" ;;
  worktree)  shift
             case "${1:-}" in
               finalize) shift
                         [ $# -gt 0 ] && die "인자가 너무 많다. usage: bouncer worktree finalize"
                         cmd_wt_finalize ;;
               create)   die "worktree는 'bouncer start <workflow> <slug> --parallel' 로 만든다." ;;
               *) die "usage: bouncer worktree finalize" ;;
             esac ;;
  ""|-h|--help) sed -n '3,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
  *) die "알 수 없는 명령: $1" ;;
esac
