#!/bin/bash
# ai-bouncer 빠른 업데이트
# 기존 설치된 파일을 소스에서 덮어쓰기 (설정 변경 없음)
# Usage: bash update.sh

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC}  $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
err()  { echo -e "${RED}✗${NC}  $*"; }

PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# PACKAGE_DIR 유효성 검사 (원격 실행 / 설치된 update.sh 대응)
if [ ! -f "$PACKAGE_DIR/agents/intent.md" ]; then
  echo -e "${BOLD}최신 소스 다운로드 중...${NC}"
  TMPDIR_UPDATE=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_UPDATE"' EXIT
  git clone --depth 1 "${AI_BOUNCER_REPO:-https://github.com/kangraemin/ai-bouncer.git}" "$TMPDIR_UPDATE/ai-bouncer" -q
  PACKAGE_DIR="$TMPDIR_UPDATE/ai-bouncer"
  echo -e "${GREEN}✓${NC}  다운로드 완료"
fi

# 설치 경로 감지: 로컬(.claude/) 우선, 글로벌(~/.claude/) fallback
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

TARGET_DIR=""

# 1. 로컬 설치 확인
if [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/.claude/ai-bouncer/config.json" ]; then
  CONFIG_FILE="$REPO_ROOT/.claude/ai-bouncer/config.json"
  TARGET_DIR=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('target_dir','$REPO_ROOT/.claude'))")
fi

# 2. 글로벌 설치 확인 (하위 호환)
if [ -z "$TARGET_DIR" ] && [ -f "$HOME/.claude/ai-bouncer/config.json" ]; then
  CONFIG_FILE="$HOME/.claude/ai-bouncer/config.json"
  TARGET_DIR=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('target_dir','$HOME/.claude'))")
fi

if [ -z "$TARGET_DIR" ]; then
  err "ai-bouncer가 설치되어 있지 않습니다. install.sh를 먼저 실행하세요."
  exit 1
fi

BOUNCER_DATA_DIR="$TARGET_DIR/ai-bouncer"

echo -e "${BOLD}ai-bouncer 업데이트${NC} → $TARGET_DIR"
echo ""

# agents (동적 복사 — agents/*.md)
for agent in "$PACKAGE_DIR/agents/"*.md; do
  [ -f "$agent" ] || continue
  dst="$TARGET_DIR/agents/$(basename "$agent")"
  mkdir -p "$(dirname "$dst")"
  cp "$agent" "$dst"
  ok "$(basename "$agent") (agent)"
done

# agents 서브디렉토리 (guides/ 등) 동적 복사
for subdir in "$PACKAGE_DIR/agents"/*/; do
  [ -d "$subdir" ] || continue
  dir_name=$(basename "$subdir")
  mkdir -p "$TARGET_DIR/agents/$dir_name"
  for f in "$subdir"*.md; do
    [ -f "$f" ] || continue
    cp "$f" "$TARGET_DIR/agents/$dir_name/$(basename "$f")"
    ok "$(basename "$f") (agents/$dir_name)"
  done
done

# 소스에 없는 설치된 agent 파일 삭제 (manifest에 기록된 파일만 대상)
MANIFEST="$BOUNCER_DATA_DIR/manifest.json"
for installed in "$TARGET_DIR/agents/"*.md; do
  [ -f "$installed" ] || continue
  rel_path="agents/$(basename "$installed")"
  # manifest에 없으면 사용자가 직접 추가한 파일 → 스킵
  if [ -f "$MANIFEST" ] && ! python3 -c "import json,sys; files=json.load(open(sys.argv[1])).get('files',[]); sys.exit(0 if sys.argv[2] in files else 1)" "$MANIFEST" "$rel_path" 2>/dev/null; then
    continue
  fi
  if [ ! -f "$PACKAGE_DIR/agents/$(basename "$installed")" ]; then
    rm -f "$installed"
    warn "$(basename "$installed") 삭제 (소스에서 제거됨)"
  fi
done

# skills (로컬 설치)
SKILL_DST="$TARGET_DIR/skills/dev-bounce"
mkdir -p "$SKILL_DST"
cp -r "$PACKAGE_DIR/skills/dev-bounce/." "$SKILL_DST/"
ok "dev-bounce (skill)"

# hooks (managed block 교체)
install_hook() {
  local src="$1" dst="$2"
  local START="# --- ai-bouncer start ---"
  local END="# --- ai-bouncer end ---"

  mkdir -p "$(dirname "$dst")"

  if [ ! -f "$dst" ]; then
    cp "$src" "$dst"
    chmod +x "$dst"
    ok "$(basename "$dst") (새로 설치)"
    return
  fi

  python3 - "$src" "$dst" "$START" "$END" <<'PYEOF'
import sys, re

src_path, dst_path = sys.argv[1], sys.argv[2]
start_marker, end_marker = sys.argv[3], sys.argv[4]

src = open(src_path, encoding='utf-8').read()
dst = open(dst_path, encoding='utf-8').read()

s_start = src.find(start_marker)
s_end   = src.find(end_marker)

if s_start == -1 or s_end == -1:
    open(dst_path, 'w', encoding='utf-8').write(src)
    sys.exit(0)

managed_block = src[s_start : s_end + len(end_marker)]

d_start = dst.find(start_marker)
d_end   = dst.find(end_marker)

if d_start != -1 and d_end != -1:
    new_dst = dst[:d_start] + managed_block + dst[d_end + len(end_marker):]
else:
    exit_match = re.search(r'^exit\s+0\s*$', dst, re.MULTILINE)
    if exit_match:
        pos = exit_match.start()
        new_dst = dst[:pos] + managed_block + '\n\n' + dst[pos:]
    else:
        new_dst = dst.rstrip('\n') + '\n\n' + managed_block + '\n'

open(dst_path, 'w', encoding='utf-8').write(new_dst)
PYEOF
  chmod +x "$dst"
  ok "$(basename "$dst") (hook)"
}

# enforcement_mode 확인 — prompt-only면 hook 복사 스킵
ENFORCEMENT_MODE=$(jq -r '.enforcement_mode // "hooks"' "$CONFIG_FILE" 2>/dev/null || echo "hooks")

# hooks.json 매니페스트 기반 동적 설치
HOOKS_MANIFEST="$PACKAGE_DIR/hooks/hooks.json"
if [ -f "$HOOKS_MANIFEST" ] && [ "$ENFORCEMENT_MODE" = "hooks" ]; then
  # hooks.json 자체도 복사
  mkdir -p "$TARGET_DIR/hooks"
  cp "$HOOKS_MANIFEST" "$TARGET_DIR/hooks/hooks.json"
  ok "hooks.json (manifest)"

  python3 -c "
import json, sys
manifest = json.load(open(sys.argv[1]))
for hook_type, hooks in manifest.items():
    for h in hooks:
        print(h['type'], h['file'])
" "$HOOKS_MANIFEST" | while read -r htype hfile; do
    src="$PACKAGE_DIR/hooks/$hfile"
    dst="$TARGET_DIR/hooks/$hfile"
    [ -f "$src" ] || continue
    if [ "$htype" = "managed" ]; then
      install_hook "$src" "$dst"
    else
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst"
      chmod +x "$dst"
      ok "$hfile (hook)"
    fi
  done
else
  ok "hook 복사 스킵 (enforcement_mode=prompt-only)"
fi

# hooks/lib/ 동적 복사
if [ -d "$PACKAGE_DIR/hooks/lib" ]; then
  mkdir -p "$TARGET_DIR/hooks/lib"
  for lib in "$PACKAGE_DIR/hooks/lib/"*.sh; do
    [ -f "$lib" ] || continue
    cp "$lib" "$TARGET_DIR/hooks/lib/$(basename "$lib")"
    chmod +x "$TARGET_DIR/hooks/lib/$(basename "$lib")"
    ok "$(basename "$lib") (lib)"
  done
fi

# Stop hook 호환성 패치
inject_stop_compat() {
  local src="$1" dst="$2"
  local START="# --- ai-bouncer start ---"
  local END="# --- ai-bouncer end ---"

  [ -f "$dst" ] || return 0

  python3 - "$src" "$dst" "$START" "$END" <<'PYEOF'
import sys

src_path     = sys.argv[1]
dst_path     = sys.argv[2]
start_marker = sys.argv[3]
end_marker   = sys.argv[4]

src = open(src_path, encoding='utf-8').read()
dst = open(dst_path, encoding='utf-8').read()

s_start = src.find(start_marker)
s_end   = src.find(end_marker)
if s_start == -1 or s_end == -1:
    sys.exit(0)
managed_block = src[s_start : s_end + len(end_marker)]

d_start = dst.find(start_marker)
d_end   = dst.find(end_marker)
if d_start != -1 and d_end != -1:
    new_dst = dst[:d_start] + managed_block + dst[d_end + len(end_marker):]
else:
    if dst.startswith('#!'):
        newline = dst.index('\n') + 1
        new_dst = dst[:newline] + managed_block + '\n' + dst[newline:]
    else:
        new_dst = managed_block + '\n' + dst

open(dst_path, 'w', encoding='utf-8').write(new_dst)
PYEOF
  ok "$(basename "$dst") (stop compat)"
}

patch_stop_hooks() {
  local settings_file="$1"
  [ -f "$settings_file" ] || return 0

  local stop_hooks
  stop_hooks=$(python3 -c "
import json
cfg = json.load(open('$settings_file'))
for g in cfg.get('hooks', {}).get('Stop', []):
    for h in g.get('hooks', []):
        cmd = h.get('command', '')
        if cmd and 'completion-gate' not in cmd:
            print(cmd)
" 2>/dev/null)

  [ -z "$stop_hooks" ] && return 0

  while IFS= read -r hook_path; do
    [ -f "$hook_path" ] || continue
    case "$(basename "$hook_path")" in
      completion-gate.sh|subagent-track.sh|subagent-cleanup.sh) continue ;;
    esac
    inject_stop_compat "$PACKAGE_DIR/hooks/stop-bouncer-compat.sh" "$hook_path"
  done <<< "$stop_hooks"
}

patch_stop_hooks "$HOME/.claude/settings.json"
patch_stop_hooks "$TARGET_DIR/settings.json"

# update.sh / uninstall.sh → 프로젝트 루트
if [ -n "$REPO_ROOT" ]; then
  # 동일 파일이면 복사 스킵 (로컬 실행 시 자기 자신 복사 방지)
  if [ "$(realpath "$PACKAGE_DIR/update.sh" 2>/dev/null)" != "$(realpath "$REPO_ROOT/update.sh" 2>/dev/null)" ]; then
    cp "$PACKAGE_DIR/update.sh" "$REPO_ROOT/update.sh"
    chmod +x "$REPO_ROOT/update.sh"
    ok "update.sh (프로젝트 루트)"
  fi
  if [ "$(realpath "$PACKAGE_DIR/uninstall.sh" 2>/dev/null)" != "$(realpath "$REPO_ROOT/uninstall.sh" 2>/dev/null)" ]; then
    cp "$PACKAGE_DIR/uninstall.sh" "$REPO_ROOT/uninstall.sh"
    chmod +x "$REPO_ROOT/uninstall.sh"
    ok "uninstall.sh (프로젝트 루트)"
  fi
fi

# 매니페스트 업데이트 (로컬 우선)
MANIFEST="$BOUNCER_DATA_DIR/manifest.json"
mkdir -p "$BOUNCER_DATA_DIR"
SHA=$(git -C "$PACKAGE_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
python3 -c "
import json, datetime, os
m = json.load(open('$MANIFEST')) if os.path.exists('$MANIFEST') else {}
m['version'] = '$SHA'
m['updated_at'] = datetime.datetime.now().isoformat()
json.dump(m, open('$MANIFEST','w'), indent=2)
"
ok "매니페스트 ($SHA)"

echo ""
echo -e "${GREEN}✓${NC}  ${BOLD}업데이트 완료${NC}"
