#!/usr/bin/env bash
# ai-bouncer 자동 업데이트 확인.
# SessionStart hook에서 호출된다. 세션 시작을 느리게 하면 안 되므로 타임아웃을 짧게 둔다.
#
# 기준 브랜치는 config.json의 update_branch로 정한다 (기본 main).
# dev 트랙을 타는 사용자는 `"update_branch": "dev"`만 넣으면 된다.

set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../engine/lib/common.sh"

PROJECT="${BOUNCER_PROJECT:-$PWD}"
command -v jq >/dev/null 2>&1 || exit 0
command -v curl >/dev/null 2>&1 || exit 0

REPO="$(bouncer_config repo "kangraemin/ai-bouncer" "$PROJECT")"
BRANCH="$(bouncer_config update_branch "main" "$PROJECT")"
ENABLED="$(bouncer_config update_check "true" "$PROJECT")"
INTERVAL_H="$(bouncer_config update_check_interval_hours "6" "$PROJECT")"
[ "$ENABLED" = "true" ] || exit 0

DATA_DIR="$(bouncer_data_dir "$PROJECT")"
STAMP="$DATA_DIR/.update-check"
INSTALLED="$DATA_DIR/installed.json"

# ── 확인 주기 ────────────────────────────────────────────────
now=$(date +%s)
if [ -f "$STAMP" ]; then
  last=$(cat "$STAMP" 2>/dev/null || echo 0)
  [ "$last" -eq "$last" ] 2>/dev/null || last=0
  if [ $(( now - last )) -lt $(( INTERVAL_H * 3600 )) ]; then exit 0; fi
fi
printf '%s' "$now" > "$STAMP" 2>/dev/null

# ── 현재 설치된 커밋 ──────────────────────────────────────────
local_sha=""
local_branch=""
if [ -f "$INSTALLED" ]; then
  local_sha="$(jq -r '.commit // empty' "$INSTALLED" 2>/dev/null)"
  local_branch="$(jq -r '.branch // empty' "$INSTALLED" 2>/dev/null)"
fi

# ── 원격 최신 커밋 (기준 브랜치) ──────────────────────────────
api="https://api.github.com/repos/$REPO/commits/$BRANCH"
remote="$(curl -sf --max-time 5 -H 'Accept: application/vnd.github.sha' "$api" 2>/dev/null)"
if [ -z "$remote" ]; then
  # sha 미디어타입이 막히면 JSON으로 재시도
  remote="$(curl -sf --max-time 5 "$api" 2>/dev/null | jq -r '.sha // empty' 2>/dev/null)"
fi
[ -n "$remote" ] || exit 0   # 네트워크 실패는 조용히 무시 — 세션을 막지 않는다

# ── 트랙이 바뀐 경우 ─────────────────────────────────────────
if [ -n "$local_branch" ] && [ "$local_branch" != "$BRANCH" ]; then
  printf 'ai-bouncer: 업데이트 트랙이 %s → %s 로 바뀌었습니다. `bouncer-update`로 전환하세요.\n' \
    "$local_branch" "$BRANCH"
  exit 0
fi

[ "$local_sha" = "$remote" ] && exit 0

short_l="${local_sha:0:7}"; short_r="${remote:0:7}"
printf 'ai-bouncer: 새 버전이 있습니다 (%s: %s → %s). 적용하려면 `bouncer-update`.\n' \
  "$BRANCH" "${short_l:-미상}" "$short_r"
exit 0
