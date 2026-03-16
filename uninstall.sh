#!/bin/bash
# ai-bouncer uninstall
# Usage: bash uninstall.sh

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ok()     { echo -e "${GREEN}✓${NC}  $*"; }
info()   { echo -e "${BLUE}ℹ${NC}  $*"; }
warn()   { echo -e "${YELLOW}⚠${NC}  $*"; }
err()    { echo -e "${RED}✗${NC}  $*"; }
header() { echo -e "\n${BOLD}── $* ──${NC}\n"; }

header "ai-bouncer 제거"

# 설치 범위 감지: 로컬(.claude/ai-bouncer/) → 글로벌(~/.claude/ai-bouncer/) 순서
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
TARGET_DIR=""

# 1. 로컬 설치 확인
if [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/.claude/ai-bouncer/manifest.json" ]; then
  TARGET_DIR="$REPO_ROOT/.claude"
fi

# 2. 글로벌 설치 확인 (하위 호환)
if [ -z "$TARGET_DIR" ] && [ -f "$HOME/.claude/ai-bouncer/manifest.json" ]; then
  TARGET_DIR="$HOME/.claude"
fi

if [ -z "$TARGET_DIR" ]; then
  err "설치된 ai-bouncer를 찾을 수 없습니다."
  exit 1
fi

BOUNCER_DATA_DIR="$TARGET_DIR/ai-bouncer"
MANIFEST="$BOUNCER_DATA_DIR/manifest.json"
info "매니페스트에서 설치 파일 목록 읽는 중... ($MANIFEST)"

python3 - "$MANIFEST" "$TARGET_DIR" <<'PYEOF'
import json, os, sys

manifest_path = sys.argv[1]
target_dir = sys.argv[2]

try:
    with open(manifest_path) as f:
        manifest = json.load(f)
except (json.JSONDecodeError, FileNotFoundError) as e:
    print(f"  ⚠ 매니페스트 읽기 실패: {e}")
    print("  파일 삭제를 건너뛰고 설정 정리를 계속합니다.")
    sys.exit(0)

removed = 0
for rel_path in manifest.get('files', []):
    abs_path = os.path.join(target_dir, rel_path)
    if os.path.exists(abs_path):
        os.remove(abs_path)
        print(f"  삭제: {rel_path}")
        removed += 1

print(f"\n  {removed}개 파일 삭제됨 (백업 파일은 유지)")
PYEOF

# Stop hook에서 ai-bouncer 블록 제거 (settings.json 정리 전에 수행)
remove_bouncer_block() {
  local file="$1"
  [ -f "$file" ] || return 0
  python3 - "$file" <<'PYEOF'
import sys
f = sys.argv[1]
START = "# --- ai-bouncer start ---"
END = "# --- ai-bouncer end ---"
content = open(f, encoding='utf-8').read()
s = content.find(START)
e = content.find(END)
if s == -1 or e == -1:
    sys.exit(0)
before = content[:s].rstrip('\n')
after = content[e + len(END):].lstrip('\n')
new = (before + '\n\n' + after).strip('\n') + '\n'
open(f, 'w', encoding='utf-8').write(new)
print(f"  {f}: ai-bouncer 블록 제거됨")
PYEOF
}

for settings_file in "$HOME/.claude/settings.json" "$TARGET_DIR/settings.json"; do
  [ -f "$settings_file" ] || continue
  python3 -c "
import json
cfg = json.load(open('$settings_file'))
for g in cfg.get('hooks', {}).get('Stop', []):
    for h in g.get('hooks', []):
        cmd = h.get('command', '')
        if cmd: print(cmd)
" 2>/dev/null | while IFS= read -r hook_path; do
    remove_bouncer_block "$hook_path"
  done
done

# settings.json에서 hook 제거
SETTINGS_FILE="$TARGET_DIR/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
  python3 - "$SETTINGS_FILE" <<'PYEOF'
import json, sys

settings_file = sys.argv[1]

with open(settings_file) as f:
    cfg = json.load(f)

BOUNCER_HOOKS = {
    'plan-gate.sh', 'bash-gate.sh', 'bash-audit.sh',
    'doc-reminder.sh', 'completion-gate.sh',
    'subagent-track.sh', 'subagent-cleanup.sh',
}

def is_bouncer_hook(group):
    for h in group.get('hooks', []):
        cmd = h.get('command', '')
        # 파일명 기준 매칭 (경로 무관)
        import os
        if os.path.basename(cmd) in BOUNCER_HOOKS:
            return True
    return False

hooks = cfg.get('hooks', {})
for hook_type in ['PreToolUse', 'PostToolUse', 'Stop', 'SubagentStart', 'SubagentStop']:
    if hook_type in hooks:
        original = hooks[hook_type]
        filtered = [g for g in original if not is_bouncer_hook(g)]
        if len(filtered) != len(original):
            hooks[hook_type] = filtered
            print(f"  {hook_type} hook 제거됨")

# 빈 hook 타입 정리
hooks = {k: v for k, v in hooks.items() if v}
if hooks:
    cfg['hooks'] = hooks
else:
    cfg.pop('hooks', None)

# AGENT_TEAMS env 제거
env = cfg.get('env', {})
env.pop('CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS', None)
if not env:
    cfg.pop('env', None)
else:
    cfg['env'] = env

with open(settings_file, 'w') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write('\n')
PYEOF
fi

# CLAUDE.md 블록 제거
CLAUDE_FILE="$TARGET_DIR/CLAUDE.md"
if [ -f "$CLAUDE_FILE" ]; then
  python3 - "$CLAUDE_FILE" <<'PYEOF'
import sys

claude_file = sys.argv[1]
START = "# --- ai-bouncer-rule start ---"
END   = "# --- ai-bouncer-rule end ---"

content = open(claude_file, encoding='utf-8').read()
s = content.find(START)
e = content.find(END)

if s == -1 or e == -1:
    print("  CLAUDE.md 블록 없음 (no-op)")
    sys.exit(0)

# 마커 포함 블록 제거, 앞뒤 빈줄 정리 (섹션 간 이중 개행 보존)
before = content[:s].rstrip('\n')
after  = content[e + len(END):].lstrip('\n')
new_content = (before + '\n\n' + after).strip('\n')
if new_content:
    new_content += '\n'
else:
    # CLAUDE.md가 bouncer 규칙만 있었으면 파일 삭제
    import os
    os.remove(claude_file)
    print("  CLAUDE.md 삭제됨 (bouncer 규칙만 있었음)")
    sys.exit(0)

open(claude_file, 'w', encoding='utf-8').write(new_content)
print("  CLAUDE.md ai-bouncer 규칙 블록 제거됨")
PYEOF
fi

# 빈 디렉토리 정리
for dir in "$TARGET_DIR/hooks/lib" "$TARGET_DIR/hooks" \
           "$TARGET_DIR/agents/guides" "$TARGET_DIR/agents" \
           "$TARGET_DIR/skills/dev-bounce" "$TARGET_DIR/skills"; do
  rmdir "$dir" 2>/dev/null || true
done

# 매니페스트/config 삭제
rm -f "$BOUNCER_DATA_DIR/manifest.json"
rm -f "$BOUNCER_DATA_DIR/config.json"
rmdir "$BOUNCER_DATA_DIR" 2>/dev/null || true

# 프로젝트 루트의 update.sh / uninstall.sh 삭제
if [ -n "$REPO_ROOT" ]; then
  rm -f "$REPO_ROOT/update.sh"
  rm -f "$REPO_ROOT/uninstall.sh"
fi

echo ""
ok "ai-bouncer 제거 완료"
