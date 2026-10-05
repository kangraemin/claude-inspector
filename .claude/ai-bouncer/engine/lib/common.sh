#!/usr/bin/env bash
# ai-bouncer 공용 라이브러리 — 경로 해석, 상태 접근.
# hook과 CLI가 모두 source한다. 런타임 의존성은 jq 하나.

set -uo pipefail

BOUNCER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOUNCER_ROOT="$(cd "$BOUNCER_LIB_DIR/../.." && pwd)"

# ── 경로 ─────────────────────────────────────────────────────
# 설치는 프로젝트별로만 한다. 전역 설치는 없다 —
# 레포마다 워크플로우가 다른 게 정상이고, 전역을 두면 "어느 설정이 이겼나"를
# 매번 따져야 한다. 필요해지면 그때 더한다.
#
#   <프로젝트>/.claude/ai-bouncer/   설정 + 엔진 (workflow.yaml, hooks, engine)
#   <프로젝트>/.ai-bouncer/          런타임 상태 (state.json, .active)
# 설치 지점을 현재 위치에서 위로 올라가며 찾는다.
# 하위 디렉토리나 worktree에서 실행하면 작업이 사라진 것처럼 보이던 원인이다.
# 병렬 작업용 worktree 안에서도 **메인 레포**를 프로젝트로 본다.
# worktree에는 .claude/ai-bouncer/ 가 git으로 딸려오므로, 위로 올라가는 탐색만 하면
# worktree 자신을 프로젝트로 판정하고 거기 .ai-bouncer/tasks 가 비어 있어
# 모든 hook이 조용히 무관여가 된다 (push 통과, Stop 무출력).
# git-common-dir 은 worktree에서도 메인 레포의 .git 을 가리킨다.
bouncer_main_root() {
  local d="${1:-$PWD}" gcd
  gcd="$(git -C "$d" rev-parse --git-common-dir 2>/dev/null)" || return 1
  [ -n "$gcd" ] || return 1
  case "$gcd" in /*) ;; *) gcd="$(cd "$d" && cd "$gcd" 2>/dev/null && pwd)" || return 1 ;; esac
  [ -d "$gcd" ] || return 1
  printf '%s' "$(dirname "$gcd")"
}
bouncer_project_root() {
  local d="${1:-$PWD}" main
  d="$(cd "$d" 2>/dev/null && pwd)" || { printf '%s' "${1:-$PWD}"; return; }
  # worktree라면 메인 레포로 건너뛴다. 설치가 거기 있어야 상태를 공유한다.
  if main="$(bouncer_main_root "$d")" && [ "$main" != "$d" ] \
     && [ -f "$main/.claude/ai-bouncer/workflow.yaml" ]; then
    printf '%s' "$main"; return
  fi
  while [ "$d" != "/" ]; do
    [ -f "$d/.claude/ai-bouncer/workflow.yaml" ] && { printf '%s' "$d"; return; }
    d="$(dirname "$d")"
  done
  # 설치를 못 찾으면 git 루트, 그것도 없으면 준 경로 그대로
  d="$(git -C "${1:-$PWD}" rev-parse --show-toplevel 2>/dev/null)" \
    && { printf '%s' "$d"; return; }
  printf '%s' "${1:-$PWD}"
}
bouncer_data_dir()      { printf '%s/.claude/ai-bouncer'                    "$(bouncer_project_root "${1:-$PWD}")"; }
bouncer_workflow_yaml() { printf '%s/.claude/ai-bouncer/workflow.yaml'      "$(bouncer_project_root "${1:-$PWD}")"; }
bouncer_compiled_file() { printf '%s/.claude/ai-bouncer/workflow.compiled.json' "$(bouncer_project_root "${1:-$PWD}")"; }
bouncer_tasks_dir()     { printf '%s/.ai-bouncer/tasks'                     "$(bouncer_project_root "${1:-$PWD}")"; }

# 설정은 workflow.yaml의 settings 섹션에 있고, 컴파일되어 compiled.json에 들어간다.
# 별도 config 파일은 없다.
bouncer_config() {
  local key="$1" default="${2:-}" project="${3:-$PWD}" f val
  f="$(bouncer_compiled_file "$project")"
  [ -f "$f" ] || { printf '%s' "$default"; return; }
  # jq 의 `//` 는 false 를 "없음" 으로 본다 — `update_check: false` 가 조용히
  # 무시됐다. choices 에서 같은 함정을 이미 고쳤는데 여기만 남아 있었다.
  val="$(jq -r --arg k "$key" \
    'if (.settings | has($k)) then .settings[$k] else empty end' "$f" 2>/dev/null)"
  [ -n "${val:-}" ] && printf '%s' "$val" || printf '%s' "$default"
}

# ── 활성 태스크 ──────────────────────────────────────────────
# 이 세션이 소유한 .active만 찾는다. 남의 것은 읽지도 건드리지도 않는다.
bouncer_my_task() {
  local project="${1:-$PWD}" session="${2:-}" tasks active owner
  [ -n "$session" ] || return 1
  tasks="$(bouncer_tasks_dir "$project")"
  [ -d "$tasks" ] || return 1
  for active in "$tasks"/*/.active; do
    [ -f "$active" ] || continue
    owner="$(jq -r '.session_id // empty' "$active" 2>/dev/null)"
    if [ "$owner" = "$session" ]; then dirname "$active"; return 0; fi
  done
  return 1
}

# lock의 나이(초). 하트비트는 Stop hook이 갱신한다.
# CLI는 곧바로 종료되므로 pid로 생존을 판정할 수 없다 — 그래서 시간 기반이다.
# 시각을 읽을 수 없는 락은 "방금 갱신됨"이 아니라 "손상됨"이다.
# 0을 돌려주면 12시간 정리에 영원히 안 걸려 좀비 락이 된다.
# 파일 수정 시각으로 대체하고, 그것도 안 되면 아주 오래된 것으로 취급한다.
bouncer_lock_age() {
  local seen now t
  now=$(date -u +%s)
  seen="$(jq -r '.seen_at // .claimed_at // empty' "$1" 2>/dev/null)"
  if [ -n "$seen" ]; then
    t=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$seen" +%s 2>/dev/null) \
      || t=$(date -u -d "$seen" +%s 2>/dev/null) || t=""
  fi
  if [ -z "${t:-}" ]; then
    t=$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null) || t=0
  fi
  # 미래 시각이면 시계가 어긋난 것 — 음수 대신 0으로 눕힌다
  local age=$(( now - t )); [ "$age" -lt 0 ] && age=0
  printf '%s' "$age"
}

# 읽을 수 없는(손상된) 락인지 — 소유자 판별이 안 되면 아무도 해제할 수 없다.
# 이런 락은 시간과 무관하게 회수 대상이다. 안 그러면 영구 데드락이 된다.
bouncer_lock_broken() {
  [ -f "$1" ] || return 0
  jq -e 'type == "object" and (.session_id | type == "string") and (.session_id | length > 0)' \
     "$1" >/dev/null 2>&1 && return 1 || return 0
}

bouncer_touch_lock() {
  # tmp 이름을 공유하면 동시에 도는 프로세스끼리 서로의 임시 파일을 mv 해
  # 원본이 빈 파일로 바뀐다. 프로세스별로 다른 이름을 쓴다.
  local f="$1/.active" tmp="$1/.active.$$.tmp"
  [ -f "$f" ] || return 0
  if jq --arg t "$(date -u +%FT%TZ)" '.seen_at = $t' "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv "$tmp" "$f"
  else
    rm -f "$tmp"
  fi
}

# 세션 무관하게 존재하는 모든 lock (충돌 안내용).
bouncer_live_locks() {
  local tasks active
  tasks="$(bouncer_tasks_dir "${1:-$PWD}")"
  [ -d "$tasks" ] || return 0
  for active in "$tasks"/*/.active; do
    [ -f "$active" ] && dirname "$active"
  done
}

# ── state.json ───────────────────────────────────────────────
bouncer_state() { jq -r "${2} // empty" "$1/state.json" 2>/dev/null; }

# 실패하면 원본을 건드리지 않고 1을 반환한다. 호출부는 반환값을 확인해야 한다.
#
# tmp+mv 는 교체를 원자적으로 만들지만 read-modify-write 전체를 직렬화하지는 않는다.
# 동시에 여러 프로세스가 각자 읽고 자기 키만 얹어 쓰면 마지막 것만 남는다(lost update).
# mkdir 은 원자적이라 그것으로 짧은 임계구역을 만든다.
bouncer_state_update() {
  local dir="$1"; shift
  local f="$dir/state.json" lock="$dir/.lock" tmp="$dir/.state.$$.tmp"
  [ -f "$f" ] || return 1

  local i=0
  until mkdir "$lock" 2>/dev/null; do
    i=$((i+1))
    # 잠금을 쥔 프로세스가 죽었을 수 있다. 오래된 것은 걷어낸다.
    if [ "$i" -gt 50 ]; then
      local age
      age=$(( $(date +%s) - $(stat -f %m "$lock" 2>/dev/null || stat -c %Y "$lock" 2>/dev/null || echo 0) ))
      [ "$age" -gt 30 ] && rm -rf "$lock" || return 1
    fi
    sleep 0.02
  done

  local rc=0
  if jq "$@" "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
    mv "$tmp" "$f"
  else
    rm -f "$tmp"; rc=1
  fi
  rmdir "$lock" 2>/dev/null
  return $rc
}

# 죽은 프로세스가 남긴 임시 파일을 걷어낸다. 누적되면 디렉토리가 지저분해진다.
bouncer_sweep_tmp() {
  local d="$1" f pid
  for f in "$d"/.state.*.tmp "$d"/.active.*.tmp; do
    [ -f "$f" ] || continue
    pid="${f##*.state.}"; pid="${pid##*.active.}"; pid="${pid%%.tmp}"
    case "$pid" in ''|*[!0-9]*) rm -f "$f"; continue ;; esac
    kill -0 "$pid" 2>/dev/null || rm -f "$f"
  done
}

# ── 워크플로우 정의 ──────────────────────────────────────────
bouncer_stage()  { jq -c --arg s "$2" '.stages[$s] // empty' "$(bouncer_compiled_file "$1")" 2>/dev/null; }
bouncer_chain()  { jq -r --arg w "$2" '.workflows[$w].stages[]? // empty' "$(bouncer_compiled_file "$1")" 2>/dev/null; }
bouncer_next_stage() {
  jq -r --arg w "$2" --arg c "$3" '
    (.workflows[$w].stages // []) as $st
    | ($st | index($c)) as $i
    | if $i == null then "" else ($st[$i+1] // "") end
  ' "$(bouncer_compiled_file "$1")" 2>/dev/null
}
bouncer_is_last_stage() {
  jq -e --arg w "$2" --arg c "$3" '
    (.workflows[$w].stages // []) | (index($c) != null and index($c) == (length - 1))
  ' "$(bouncer_compiled_file "$1")" >/dev/null 2>&1
}

# 작업 트리의 "내용" 지문. status --porcelain 은 경로와 상태 문자만 주므로
# 이미 수정된 파일을 다시 고쳐도 값이 같다 — 그걸로 비교하면 영원히 "안 바뀜"이 된다.
# git 을 쓸 수 없으면 빈 값을 돌려준다. 호출부는 그때 비교를 건너뛴다.
bouncer_tree_hash() {
  local w="${1:-$PWD}"
  git -C "$w" rev-parse --git-dir >/dev/null 2>&1 || { printf ''; return; }
  {
    git -C "$w" rev-parse HEAD 2>/dev/null
    git -C "$w" diff HEAD 2>/dev/null
    git -C "$w" ls-files -o --exclude-standard -z 2>/dev/null \
      | xargs -0 shasum -a 256 2>/dev/null
  } | shasum -a 256 | cut -d' ' -f1
}

# ── hook 출력 ────────────────────────────────────────────────
bouncer_block()   { jq -n --arg r "$1" '{decision:"block", reason:$r}'; exit 0; }   # PreToolUse 차단 / Stop 계속
bouncer_notice()  { jq -n --arg c "$1" '{hookSpecificOutput:{additionalContext:$c}}'; exit 0; }
