#!/usr/bin/env bash
# SessionStart — 컴파일 최신화, 죽은 lock 정리, 진행 중 작업 복원.
# stdout이 그대로 모델 컨텍스트에 들어간다.

set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../engine/lib/common.sh"

INPUT="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || exit 0

SESSION="$(jq -r '.session_id // empty' <<<"$INPUT" 2>/dev/null)"
CWD="$(jq -r '.cwd // empty'            <<<"$INPUT" 2>/dev/null)"
[ -n "$CWD" ] || CWD="$PWD"

YAML="$(bouncer_workflow_yaml "$CWD")"
COMPILED="$(bouncer_compiled_file "$CWD")"
[ -f "$YAML" ] || exit 0

# ── 1. 필요할 때만 재컴파일 ──────────────────────────────────
# yaml + 참조된 프롬프트 파일 전체의 해시를 비교한다. 프롬프트만 고쳐도 반영된다.
need_compile=1
if [ -f "$COMPILED" ]; then
  old="$(jq -r '.source_sha256 // empty' "$COMPILED" 2>/dev/null)"
  new="$(cd "$(dirname "$YAML")" && jq -r '.sources[]?' "$COMPILED" 2>/dev/null \
          | xargs -I{} cat {} 2>/dev/null | shasum -a 256 | cut -d' ' -f1)"
  [ -n "$old" ] && [ "$old" = "$new" ] && need_compile=0
fi
if [ "$need_compile" = "1" ]; then
  ENGINE="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/engine/compile.py"
  if ! err="$(python3 "$ENGINE" "$YAML" "$COMPILED" 2>&1)"; then
    # 실패해도 기존 compiled.json은 원자적 교체 덕에 그대로 살아 있다.
    printf '⚠️ ai-bouncer: workflow.yaml을 컴파일하지 못했다. 이전 설정으로 계속한다.\n%s\n' "$err"
  fi
fi

# ── 2. 오래 방치된 lock 정리 ─────────────────────────────────
# SessionEnd가 못 뜨는 강제 종료(kill -9 등)에 대한 안전망.
# 하트비트(seen_at)가 오래 멈춘 것만. 기준을 넉넉히 잡아 남의 작업을 뺏지 않는다.
STALE_H="$(bouncer_config stale_lock_hours 12 "$CWD")"
TASKS="$(bouncer_tasks_dir "$CWD")"
if [ -d "$TASKS" ]; then
  for active in "$TASKS"/*/.active; do
    [ -f "$active" ] || continue
    age="$(bouncer_lock_age "$active")"
    [ "$age" -gt $(( STALE_H * 3600 )) ] 2>/dev/null || continue
    rm -f "$active"
    printf 'ℹ️ ai-bouncer: %s시간 넘게 멈춘 잠금을 정리했다 — %s\n' \
      "$STALE_H" "$(basename "$(dirname "$active")")"
  done
fi

# ── 3. 시작 전에 알아야 할 것을 주입 ─────────────────────────
# 모델이 `bouncer scan`을 부를 필요가 없도록 여기서 미리 준다.
COMPILED_OK=0
[ -f "$COMPILED" ] && jq -e . "$COMPILED" >/dev/null 2>&1 && COMPILED_OK=1

if [ "$COMPILED_OK" = 1 ]; then
  if [ -n "$SESSION" ] && TASK="$(bouncer_my_task "$CWD" "$SESSION")"; then
    WF="$(bouncer_state "$TASK" '.workflow')"
    printf '\n[ai-bouncer] 이 세션에 진행 중인 작업이 있다: %s\n' "$(bouncer_state "$TASK" '.task_id')"
    printf '  워크플로우 %s / 현재 단계 %s\n  체인: %s\n' \
      "$WF" "$(bouncer_state "$TASK" '.current_stage')" "$(bouncer_chain "$CWD" "$WF" | tr '\n' ' ')"
    printf '  `bouncer status`로 남은 조건을 확인하고 이어서 진행해라.\n'
  else
    OTHERS=""
    for d in $(bouncer_live_locks "$CWD"); do
      OTHERS="$OTHERS  - $(basename "$d") ($(bouncer_state "$d" '.current_stage'))"$'\n'
    done
    printf '\n[ai-bouncer] 개발 작업은 /dev-bounce 로 시작한다. 사용 가능한 모드:\n'
    jq -r '.workflows | to_entries[] | "  \(.key) — \(.value.label)"' "$COMPILED"
    if [ -n "$OTHERS" ]; then
      printf '  ⚠️ 다른 세션이 잡고 있는 작업:\n%s' "$OTHERS"
      printf '  같은 트리에서 동시에 진행하면 충돌한다 — 병렬로 하려면 --parallel 을 쓴다.\n'
    fi
  fi
fi

# ── 4. 업데이트 확인 ─────────────────────────────────────────
UPD="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/scripts/update-check.sh"
[ -x "$UPD" ] && BOUNCER_PROJECT="$CWD" bash "$UPD" 2>/dev/null || true
exit 0
