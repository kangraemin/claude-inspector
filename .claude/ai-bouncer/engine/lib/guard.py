#!/usr/bin/env python3
# 셸 명령이 이 스테이지에서 허용되는지 판정한다.
#
# 네 차례 감사에서 배운 것:
#  · 블랙리스트(쓰는 명령 열거)는 원리상 완결되지 않는다.
#  · 허용 목록만으로도 부족하다 — 목록 안의 명령에도 쓰기 모드가 있다
#    (`sed 1w out`, `sort -o`, `uniq in out`, `git symbolic-ref HEAD ref`).
#  · 판정 단위는 반드시 **세그먼트**여야 한다. 줄 전체의 첫 토큰만 보면
#    `bouncer status && rm -rf x` 가 통째로 통과한다.
#  · 래퍼(`env`, `nohup`, `xargs`…)와 환경변수 접두는 실행 파일 이름을 바꾼다.
#  · 문자열이 아니라 변수로 넘긴 경로는 들여다볼 수 없다 → 그런 형태는 거부한다.
#
# 이건 샌드박스가 아니라 가드레일이다. 진짜 보장은 blocking 게이트가 한다.
#
# stdin: 명령 문자열 / argv: <edit_files_json> <push_bool> <bash_patterns_json> <project_dir>
# 출력: 차단 사유 (없으면 허용)
import json
import os
import re
import shlex
import sys

# 두 가지로 쓰인다:
#   guard.py --check-path <edit_json> <project> <파일경로>   Edit/Write 판정
#   guard.py <edit_json> <push> <patterns_json> <project> [worktree]  Bash 판정 (stdin=명령)
# 예전에는 Edit 판정을 셸 `case` 로 따로 구현해서, 같은 파일에 대해
# `*` 의 의미(`/` 를 넘는지)와 `!` 우선순위가 두 게이트에서 정반대였다.
if len(sys.argv) > 1 and sys.argv[1] == '--check-path':
    CHECK_PATH = True
    EDIT = json.loads(sys.argv[2])
    PROJECT = sys.argv[3]
    TARGET = sys.argv[4]
    CWD = sys.argv[5] if len(sys.argv) > 5 else PROJECT
    WORKTREE = sys.argv[6] if len(sys.argv) > 6 else ''
    CMD, PUSH, PATTERNS = '', False, []
else:
    CHECK_PATH = False
    CMD = sys.stdin.read()
    EDIT = json.loads(sys.argv[1])      # true / 글로브 배열 / null
    PUSH = sys.argv[2] == "true"
    PATTERNS = json.loads(sys.argv[3])
    PROJECT = sys.argv[4]
    WORKTREE = sys.argv[5] if len(sys.argv) > 5 else ''
    CWD = sys.argv[6] if len(sys.argv) > 6 else PROJECT
    TARGET = ''


def _real(p):
    """심볼릭 링크까지 푼 절대경로. 링크로 우회하는 경로를 같은 이름으로 모은다."""
    try:
        return os.path.realpath(p) if p else ''
    except (OSError, ValueError):
        # 자리표시 토큰이 경로 성분에 들어가면 realpath 가 ValueError 를 던진다.
        # 잡지 않으면 판정기가 죽고 hook 이 모든 명령을 막는다.
        return os.path.normpath(p) if p else ''


PROJECT = _real(PROJECT)
WORKTREE = _real(WORKTREE)
CWD = _real(CWD) or PROJECT

# 파일을 쓰지 않는 것으로 확인된 명령만.
# python/node/ruby/perl 은 임의 코드를 실행하므로 없다. awk 는 프로그램을 따로 본다.
READ_ONLY = {
    'ls', 'cat', 'head', 'tail', 'wc', 'file', 'stat', 'pwd', 'echo', 'printf',
    'basename', 'dirname', 'realpath', 'readlink', 'du', 'df', 'tree', 'which',
    'type', 'date', 'whoami', 'uname', 'hostname', 'id', 'true', 'false',
    'test', '[', 'command', 'env', 'printenv', 'ps', 'sw_vers', 'locale',
    'cd', 'pushd', 'popd', 'dirs',
    'grep', 'egrep', 'fgrep', 'rg', 'ag', 'ack', 'fd',
    'diff', 'cmp', 'comm', 'cut', 'tr', 'column', 'nl', 'rev', 'tac',
    'fold', 'expand', 'paste', 'join', 'od', 'strings', 'seq',
    'jq', 'shasum', 'md5sum', 'sha256sum', 'tar',
    'sort', 'find', 'sed', 'xxd', 'base64', 'uniq', 'git',   # 인자를 따로 본다
    'awk', 'gawk', 'mawk', 'nawk',                           # 프로그램을 따로 본다
}
# 스코프 모드에서 "이 명령이 인자로 준 경로를 쓴다"고 보는 것들.
# 여기 없는 명령(npm, make, ./build.sh)은 통과한다 — 셸 문법만으로 무엇을 쓰는지
# 확정할 수 없기 때문이다. 이건 가드레일이지 샌드박스가 아니다.
# 값은 "어느 인자가 쓰기 대상인가" 다. `cp a.js src/b.js` 에서 a.js는 읽기이므로
# 전부 대조하면 스코프 밖 파일을 읽기만 해도 막힌다.
#   all    모든 위치인자      last   마지막 위치인자만
#   second 두 번째 위치인자   -x     그 플래그의 값만
WRITERS = {
    'rm': 'all', 'rmdir': 'all', 'truncate': 'all', 'touch': 'all', 'shred': 'all',
    'chmod': 'all', 'chown': 'all', 'mkdir': 'all', 'unlink': 'all', 'tee': 'all',
    'patch': 'all', 'ed': 'all', 'ex': 'all', 'vim': 'all', 'vi': 'all',
    'gzip': 'all', 'gunzip': 'all', 'unzip': 'all', 'split': 'all', 'csplit': 'all',
    'cp': 'cp', 'ln': 'ln', 'install': 'last',
    # 쓰기 대상이 인자가 아니라 아카이브·패치 **내용**과 현재 디렉토리다.
    # 인자만 보면 읽기 소스밖에 안 보여 통째로 통과했다.
    'unzip': 'cwd', 'patch': 'cwd', 'cpio': 'cwd',
    'tar': 'tar',                 # 추출만 cwd 에 쓴다. 생성은 -f 대상에 쓴다
    'rsync': 'last', 'ditto': 'last',   # 마지막 위치인자가 목적지다
    'split': 'prefix', 'csplit': 'prefix',
    'mv': 'all',        # 원본이 사라지므로 원본도 쓰기 대상이다
    'xxd': 'second', 'uniq': 'second',
    'sed': 'sed', 'dd': 'dd',
    'sort': '-o', 'base64': '-o', 'curl': '-o', 'wget': '-O',
}
# 워킹트리를 통째로 되돌리는 git 서브커맨드 — 경로를 안 줘도 파일을 바꾼다
# 워킹트리 파일을 바꾸는 것들. `fetch` 는 원격만 받아오므로 뺀다.
GIT_TREE_WRITE = {'checkout', 'restore', 'reset', 'clean', 'apply', 'stash',
                  'revert', 'merge', 'rebase', 'cherry-pick', 'pull', 'switch',
                  'am', 'rm', 'mv', 'checkout-index', 'read-tree', 'sparse-checkout',
                  'bisect', 'filter-branch', 'submodule', 'worktree'}
# 같은 서브커맨드라도 이 형태는 파일을 안 바꾼다 (브랜치 생성 / 인덱스만)
# 같은 서브커맨드라도 이 형태는 워킹트리 파일을 안 바꾼다.
#   need: 이 중 하나가 있어야 하고   deny: 이건 하나도 없어야 한다
# `any(safe in cmd)` 로 보면 `restore --staged --worktree` 가 안전으로 통과했다.
GIT_TREE_SAFE = {
    'checkout':  {'need': ('-b', '-B', '--orphan'), 'deny': ('--', '-f', '--force')},
    'switch':    {'need': ('-c', '-C', '--create'), 'deny': ('-f', '--force', '--discard-changes')},
    'restore':   {'need': ('--staged',), 'deny': ('--worktree', '-W')},
    'stash':     {'need': ('list', 'show'), 'deny': ()},
    'worktree':  {'need': ('list',), 'deny': ()},
    'submodule': {'need': ('status',), 'deny': ()},
    'apply':     {'need': ('--check', '--stat', '--summary', '--numstat'), 'deny': ()},
    'merge':     {'need': ('--abort',), 'deny': ()},
    'rebase':    {'need': ('--abort', '--continue', '--skip', '--edit-todo'), 'deny': ()},
    'cherry-pick': {'need': ('--abort', '--continue', '--skip'), 'deny': ()},
    'am':        {'need': ('--abort', '--continue', '--skip'), 'deny': ()},
    'push':      {'need': ('-n', '--dry-run'), 'deny': ()},
    'clean':     {'need': ('-n', '--dry-run'), 'deny': ()},
}


def git_safe_form(sub, cmd):
    """이 서브커맨드가 아무것도 바꾸지 않는 형태인가."""
    spec = GIT_TREE_SAFE.get(sub)
    if not spec:
        return False
    return any(a in spec['need'] for a in cmd) and not any(a in spec['deny'] for a in cmd)

# 실행 파일 이름을 가리는 래퍼. 벗겨내고 진짜 명령을 봐야 한다.
# 값을 따로 받는 플래그를 같이 적어야 한다 — `nice -n 5 cp …` 에서 `5` 를
# 명령으로 착각하면 뒤의 cp 를 아예 안 보게 된다(우회) 또는 `5` 를 막는다(과차단).
WRAPPER_VALUE_FLAGS = {
    # -S/--split-string 은 값이 **명령 전체**라 건너뛰면 안 된다 (아래에서 거부한다)
    'env':        {'-u', '--unset', '-C', '--chdir'},
    'nice':       {'-n', '--adjustment'},
    'ionice':     {'-c', '-n', '--class', '--classdata'},
    'stdbuf':     {'-i', '-o', '-e', '--input', '--output', '--error'},
    'xargs':      {'-I', '-i', '-n', '-L', '-P', '-s', '-E', '-d',
                   '--replace', '--max-args', '--max-procs', '--delimiter'},
    'caffeinate': {'-t', '-w'},
    'timeout':    {'-s', '--signal', '-k', '--kill-after'},
    'command':    set(), 'nohup': set(), 'time': set(), 'setsid': set(),
    'exec':       set(), 'busybox': set(), 'doas': set(),
}
WRAPPERS = set(WRAPPER_VALUE_FLAGS)
AWK_EXES = {'awk', 'gawk', 'mawk', 'nawk'}
# timeout 은 값을 위치인자로 받는다 (`timeout 5 cmd`)
DURATION = re.compile(r'^[0-9]+(\.[0-9]+)?[smhd]?$')
# 안에 든 프로그램을 들여다볼 수 없는 것들. 인라인 코드를 주면 판정 불가다.
# 셸만 막는다. `sh -c '…'` 는 한 토큰이라 세그먼트 분리도 리다이렉트 검사도
# 통째로 비껴가서, push 금지와 엔진 보호가 한 줄로 무력화된다.
# node -e / python3 -c 까지 막는 건 의미가 없다 — 이미 npm·make·./build.sh 가
# 허용된 단계라 막아도 얻는 게 없고 흔한 관용구만 깨진다.
INTERPRETERS = {'sh', 'bash', 'zsh', 'ksh', 'dash', 'fish', 'csh', 'tcsh'}
# 인자가 곧 코드다. 플래그가 없어도 항상 불투명하다.
OPAQUE_EXE = {'eval', 'source', '.'}
SHELL_KEYWORDS = {'for', 'if', 'while', 'until', 'case', 'select', 'function',
                  'then', 'do', 'elif', 'else'}
# 뒤에 곧바로 명령이 오는 키워드. 건너뛰고 진짜 명령을 본다.
SKIP_KEYWORDS = {'if', 'then', 'elif', 'else', 'do', 'while', 'until', 'select',
                 'fi', 'done', 'esac', '!', 'time'}
INLINE_FLAGS = ('-c', '-e', '--eval', '--command', '-E', '--exec')

# ── git ──────────────────────────────────────────────────────
# 어떤 인자를 줘도 읽기인 서브커맨드
GIT_READ = {
    'status', 'log', 'diff', 'show', 'rev-parse', 'rev-list', 'ls-files',
    'ls-tree', 'ls-remote', 'blame', 'describe', 'cat-file', 'shortlog',
    'whatchanged', 'grep', 'count-objects', 'var', 'name-rev', 'merge-base',
    'check-ignore', 'diff-tree', 'for-each-ref', 'show-branch', 'show-ref',
    'verify-pack', 'cherry', 'version', 'help',
}
# 인자에 따라 읽기/쓰기가 갈리는 서브커맨드.
#   first    : 첫 위치인자가 이 집합에 있어야 읽기 (None이면 위치인자 개수로만 판정)
#   bare_ok  : 위치인자 없이 쓰면 읽기인가
#   max_pos  : 허용되는 위치인자 개수 상한
#   bad      : 하나라도 있으면 쓰기로 보는 플래그
GIT_SUB = {
    'remote':       dict(first={'show', 'get-url'}, bare_ok=True,  max_pos=2, bad=set()),
    'stash':        dict(first={'list', 'show'},    bare_ok=False, max_pos=2, bad=set()),
    'worktree':     dict(first={'list'},            bare_ok=False, max_pos=1, bad=set()),
    'submodule':    dict(first={'status'},          bare_ok=True,  max_pos=1, bad=set()),
    'notes':        dict(first={'list', 'show'},    bare_ok=True,  max_pos=2, bad=set()),
    'reflog':       dict(first={'show'},            bare_ok=True,  max_pos=2, bad=set()),
    # 목록 형태만 읽기다. `git branch <이름>` 은 브랜치를 만든다.
    'branch':       dict(first=None, bare_ok=True, max_pos=0, list_flags={
                             '-l', '--list', '--contains', '--no-contains',
                             '--merged', '--no-merged', '--points-at',
                             '--format', '--sort'},
                         bad={'-d', '-D', '--delete', '-m', '-M', '--move', '-c', '-C',
                              '--copy', '-f', '--force', '-u', '--set-upstream-to',
                              '--unset-upstream', '--edit-description'}),
    'tag':          dict(first=None, bare_ok=True, max_pos=0, list_flags={
                             '-l', '--list', '--contains', '--no-contains',
                             '--merged', '--no-merged', '--points-at',
                             '--format', '--sort'},
                         bad={'-d', '--delete', '-a', '-s', '-m', '-f', '--force'}),
    # 인자 하나면 읽기, 둘이면 .git/HEAD 를 다시 쓴다.
    'symbolic-ref': dict(first=None, bare_ok=True, max_pos=1, bad={'-d', '--delete'}),
    'config':       dict(first=None, bare_ok=True, max_pos=1,
                         bad={'--add', '--unset', '--unset-all', '--replace-all',
                              '--rename-section', '--remove-section', '-e', '--edit'}),
}
GIT_PUSH_SUBS = {'push', 'send-pack', 'svn', 'p4', 'request-pull'}
# 아는 서브커맨드 전부. 여기 없는 것이 서브커맨드 자리에 오면 치환에 가려진 것이다.
KNOWN_GIT_SUBS = (GIT_READ | set(GIT_SUB) | GIT_PUSH_SUBS | GIT_TREE_WRITE
                  | {'commit', 'add', 'tag', 'init', 'clone', 'fetch', 'branch',
                     'log', 'status', 'diff', 'show', 'help', 'version', 'gc',
                     'prune', 'fsck', 'bundle', 'archive', 'describe', 'blame'})

# ── 쓰기 인자 ────────────────────────────────────────────────
# 명령별로 좁혀야 한다 — `-o`는 sort에서 출력이지만 grep에서는 --only-matching,
# `-i`는 sed에서 제자리 수정이지만 base64/grep에서는 전혀 다른 뜻이다.
WRITE_FLAG_ANY = {'--output'}
WRITE_PREFIX_ANY = ('--output=',)
WRITE_FLAG_CMD = {
    'sort':   {'exact': {'-o'},   'prefix': ('-o',)},
    'base64': {'exact': {'-o'},   'prefix': ()},
    # `-ni.bak` 처럼 다른 단축 플래그와 붙어 오는 형태도 잡아야 한다
    'sed':    {'exact': set(),    'prefix': ('-i', '--in-place'), 'inshort': 'i'},
    'find':   {'exact': {'-fls'}, 'prefix': ('-fprint',)},
}
# 두 번째 위치인자를 출력 파일로 쓰는 명령 → 값을 받는 플래그를 건너뛰고 세야 한다
POSITIONAL_OUT = {
    'xxd':  {'-c', '-cols', '-g', '-groupsize', '-l', '-len', '-o', '-s', '-seek'},
    'uniq': {'-f', '-s', '-w', '--skip-fields', '--skip-chars', '--check-chars'},
}
# sed 의 w/W 명령. 주소가 앞에 붙으면(`1w`, `$w`, `1,$w`) 놓치기 쉬워 문자군을 넓게 잡는다.
# sed 의 w/W 는 두 형태로 온다. BSD sed 는 파일명 앞 공백을 요구하지 않는다.
#   1) s///w file  — 치환 명령의 플래그
#   2) [주소]w file — 단독 명령 (`1w`, `$w`, `1,$w`, `/re/,$w`)
# 넓은 정규식 하나로 잡으면 `s/word/x/` 의 정규식 안 w 까지 걸린다.
def sed_writes(script):
    """sed 스크립트가 파일을 쓰는가 (`w`/`W` 명령, `s///w` 플래그).

    정규식 하나로 잡으려니 `s/;w/x/` 의 치환문 안 `;w` 까지 걸렸다.
    스크립트를 실제로 훑어야 주소·구분자·플래그를 구분할 수 있다.
    """
    i, n = 0, len(script)

    def skip_delim(i, d):
        """구분자로 감싼 구간 하나를 지나친다."""
        i += 1
        while i < n:
            if script[i] == '\\':
                i += 2; continue
            if script[i] == d:
                return i + 1
            i += 1
        return n

    while i < n:
        c = script[i]
        if c in ' \t\n;{}':
            i += 1; continue
        if c == '#':
            while i < n and script[i] != '\n':
                i += 1
            continue
        # 주소부: /re/ 또는 \cREc 또는 숫자/$ , 뒤에 ,주소 와 ! 가 올 수 있다
        for _ in range(2):
            if i < n and script[i] == '/':
                i = skip_delim(i, '/')
            elif i < n and script[i] == '\\' and i + 1 < n:
                i = skip_delim(i + 1, script[i + 1])
            elif i < n and (script[i].isdigit() or script[i] == '$'):
                while i < n and (script[i].isdigit() or script[i] in '$~+'):
                    i += 1
            else:
                break
            if i < n and script[i] == ',':
                i += 1; continue
            break
        while i < n and script[i] in ' \t!':
            i += 1
        if i >= n:
            break
        cmd = script[i]
        if cmd in 'wW':
            return True
        if cmd in 'sy':
            d = script[i + 1] if i + 1 < n else '/'
            i = skip_delim(i + 1, d)          # 패턴
            i = skip_delim(i - 1, d)          # 치환
            flags = ''
            while i < n and script[i] not in ';\n}':
                flags += script[i]; i += 1
            if 'w' in flags or 'W' in flags:
                return True
            continue
        if cmd in 'ra':                        # r=읽기, a=추가출력 (파일 안 씀)
            while i < n and script[i] != '\n':
                i += 1
            continue
        i += 1
    return False


SED_W_SPLIT = re.compile(r'^[0-9$,~+/]*[wW]$')
# awk 프로그램 안의 쓰기·실행. 변수를 거친 리다이렉트까지 잡으려면
# 대상 형태가 아니라 `print`/`printf` 뒤의 `>` 자체를 봐야 한다.
# `|` 는 awk에서 파이프이기도 하고 정규식 대안이기도 하다. 파이프는 항상
# 문자열(명령)이나 getline 과 붙어 있으므로 그 형태만 잡는다.
# close( 는 파일을 열지 않으면 쓸 일이 없어 단독 신호로는 오탐만 낸다.
AWK_EXEC = re.compile(r'system\s*\(|ENVIRON|\|\s*["\']|["\']\s*\||getline\s*<|\|\s*getline')
AWK_STMT_SPLIT = re.compile(r'[;{}\n]')

# ── 환경변수 접두 ────────────────────────────────────────────
ENV_SAFE = {'LANG', 'TZ', 'TERM', 'NO_COLOR', 'CLICOLOR', 'COLUMNS', 'LINES'}
# 값이 그대로 실행되거나 로딩되는 것들. GIT_* 는 통째로 막는다
# (GIT_EXTERNAL_DIFF, GIT_SSH, GIT_CONFIG_KEY_n 으로 별칭 주입이 전부 가능하다).
# 접두를 넓게 잡으면 `NODE_ENV=production npm run build` 처럼 필수적인 것까지 막힌다.
# 값이 그대로 실행·로딩되는 이름만 든다.
ENV_DANGEROUS_PREFIX = ('GIT_', 'LD_', 'DYLD_', 'BASH_')
ENV_DANGEROUS_EXACT = {'PERL5OPT', 'PERL5LIB', 'PYTHONSTARTUP',
                       'NODE_OPTIONS', 'NODE_PATH', 'RUBYOPT'}
ENV_DANGEROUS = {'PATH', 'ENV', 'IFS', 'SHELL', 'EDITOR', 'VISUAL', 'PAGER'}

# 안을 들여다볼 수 없는 구문 — 무엇을 하는지 판정 불가라 거부한다
OPAQUE = {'(', ')', '{', '}', '$', '`', '<(', '>('}
# 개행도 구분자다. 빠져 있어서 `ls\nrm -rf .ai-bouncer` 가 한 세그먼트로 읽혀
# exe='ls' 하나만 판정됐다 — 읽기 전용에서 엔진 삭제까지 통과했다.
SEPARATOR_BASE = {';', '&&', '||', '|', '&', ';;', '|&', '\n'}

# 리다이렉트 연산자. 앞에 붙는 fd 번호는 별도 토큰으로 떨어지므로 여기 없다.
REDIR = re.compile(r'^(>{1,2}\|?|<|<<<|<>|&>{1,2}|>&)$')
# 엔진 소유 경로. 부분문자열이 아니라 **경로 성분**으로 본다 —
# `.ai-bouncer/tasks` 만 보면 부모인 `rm -rf .ai-bouncer` 를 놓쳐 게이트가 통째로 사라진다.
ENGINE_DIRS = (('.ai-bouncer',), ('.claude', 'ai-bouncer'))
# 병렬 작업용 worktree는 ~/.ai-bouncer/worktrees/ 에 산다. 거기 있는 소스 파일은
# 엔진 상태가 아니라 **작업 대상**이라 막으면 안 된다.
ENGINE_EXEMPT = (('.ai-bouncer', 'worktrees'),)
# settings.json 은 hook 등록을 담는다. 여기서 6개 등록을 지우면 그 뒤로
# 게이트가 통째로 사라진다 — 엔진 파일과 같은 급으로 보호한다.
ENGINE_FILES = ('workflow.compiled.json',)
ENGINE_SETTINGS = ('.claude', 'settings.json')
# 이 디렉토리 자체를 지우면 그 아래 엔진이 통째로 사라진다
ENGINE_PARENTS = ('.claude',)
ENGINE_MARKERS = ('.ai-bouncer', 'ai-bouncer/', 'workflow.compiled.json')
INLINE_CODE_EXE = {'python', 'python3', 'perl', 'ruby', 'node', 'deno', 'bun', 'php',
                   'sh', 'bash', 'zsh', 'ksh', 'dash', 'awk', 'gawk', 'mawk'}
BOUNCER_EXE = ('bouncer', 'bouncer.sh')


def is_bouncer(tok):
    """엔진 자신의 명령인가. basename만 보면 `./src/bouncer` 로 위장된다."""
    t = tok.strip('"\'').lstrip('\\')
    if '/' not in t:
        # 설치본은 PATH 에 `bouncer` 로만 놓인다. `bouncer.sh` 는 정의상
        # 엔진일 수 없는데도 면제를 받아 엔진 파일 검사까지 건너뛰었다.
        return t == 'bouncer'
    full = abspath(t)
    roots = [r for r in (PROJECT, WORKTREE) if r]
    if roots and full and not any(full.startswith(r + '/') for r in roots):
        return False        # 다른 곳에 심어둔 동명 스크립트는 엔진이 아니다
    return t.replace('\\', '/').endswith('.claude/ai-bouncer/engine/bouncer.sh')
# 엔진 파일을 **읽기만** 하는 것은 막을 이유가 없다.
# (설정을 확인하려는 것뿐인데 스테이지마다 다르게 막히면 혼란만 준다)
ENGINE_READ_OK = {
    'cat', 'head', 'tail', 'wc', 'ls', 'stat', 'file', 'tree', 'du', 'jq',
    'grep', 'egrep', 'fgrep', 'rg', 'ag', 'ack', 'diff', 'cmp', 'nl', 'od',
    'strings', 'md5sum', 'sha256sum', 'shasum', 'realpath', 'dirname', 'basename',
}


ENGINE_MSG = ("엔진 파일(.ai-bouncer/ 상태, .claude/ai-bouncer/ 설정·엔진, "
              "workflow.compiled.json)은 직접 수정할 수 없다.\n"
              "읽는 것은 자유다 — `cat`/`ls`/`grep` 으로 확인해라.\n"
              "작업 상태를 바꾸려면 `bouncer` 명령을 써라.")


def out(msg):
    sys.stdout.write(msg)
    sys.exit(0)


# 연산자는 **따옴표 밖에서만** 연산자다. shlex 는 인용 여부를 안 알려줘서,
# `awk -F '|' …` 의 `|` 가 파이프로, `grep '&&' f` 가 세그먼트 구분자로 읽혔다.
# 그래서 직접 훑는다. 반환은 (텍스트, 연산자인가) 목록.
OPS = (';;', '&&', '||', '|&', '&>>', '&>', '>>', '>|', '>&', '<<<', '<>',
       ';', '&', '|', '<', '>', '\n')
STRUCT = ('$(', '<(', '>(', '`', '{', '}', '(', ')')


# 이스케이프되지 않은 `$(` 또는 백틱 (큰따옴표 안에서도 실행된다)
_CMDSUB = re.compile(r'(?<!\\)\$\((?!\()|(?<!\\)`')
ANSI_C = {'a': '\a', 'b': '\b', 'e': '\x1b', 'E': '\x1b', 'f': '\f', 'n': '\n',
          'r': '\r', 't': '\t', 'v': '\v', '\\': '\\', "'": "'", '"': '"', '?': '?'}
HEREDOC = re.compile(r'<<-?(?!<)\s*')
ARITH = (('$((', '))'), ('$[', ']'))


def _ansi_c(body):
    """$'…' 안의 이스케이프를 푼다. bash 가 실제로 만드는 문자열을 봐야 한다."""
    out, i = [], 0
    while i < len(body):
        c = body[i]
        if c != '\\':
            out.append(c); i += 1; continue
        if i + 1 >= len(body):
            break
        e = body[i + 1]
        if e in ANSI_C:
            out.append(ANSI_C[e]); i += 2
        elif e == 'x':
            h = ''
            while len(h) < 2 and i + 2 + len(h) < len(body) \
                    and body[i + 2 + len(h)] in '0123456789abcdefABCDEF':
                h += body[i + 2 + len(h)]
            out.append(chr(int(h, 16)) if h else 'x'); i += 2 + len(h)
        elif e.isdigit():
            o = ''
            while len(o) < 3 and i + 2 + len(o) < len(body) and body[i + 2 + len(o)] in '01234567':
                o += body[i + 2 + len(o)]
            out.append(chr(int(o, 8)) if o else e); i += 2 + len(o)
        else:
            out.append(e); i += 2
    return ''.join(out)


def _match_close(t, k, oc, cc):
    """t[k] 가 여는 괄호일 때 짝이 되는 닫는 괄호 위치. 따옴표 안은 세지 않는다.

    따옴표를 무시하면 `$(grep -c ')' f)` 의 `)` 를 짝으로 잡아 내용이 잘린다.
    """
    depth, q = 0, ''
    while k < len(t):
        c = t[k]
        if q:
            if c == '\\' and q == '"':
                k += 2; continue
            if c == q:
                q = ''
            k += 1; continue
        if c in '"\'':
            q = c; k += 1; continue
        if c == '\\':
            k += 2; continue
        if c == oc:
            depth += 1
        elif c == cc:
            depth -= 1
            if depth == 0:
                return k
        k += 1
    return -1


# lex() 가 만난 명령치환 내용. 바깥 명령과 **별도 세그먼트**로 따로 판정한다.
# 예전에는 `;` 토큰으로 감싸 토큰 스트림에 끼워 넣었는데, 그러면 바깥 명령이
# 인자를 잃고(`git "$(…)" origin main` → git 세그먼트가 빈 채로) 검사를 빠져나갔다.
SUBS = []
SUB_TOKEN = '\x00SUB\x00'      # 치환이 차지한 자리. 값을 알 수 없다는 표시


def _strip_subs(body):
    """문자열에서 치환을 걷어낸 리터럴을 돌려주고, 안쪽은 SUBS 에 모은다.

    리터럴을 버리면 `"$(true)push"` 의 `push` 가 어떤 검사에도 안 닿는다.
    bash 는 치환을 빈 문자열로 만들고 그 글자를 남긴다.
    실패하면 None — 안을 못 보면 열어주지 않는다.
    """
    out_chars, k = [], 0
    while k < len(body):
        if body.startswith('$(', k) and (k == 0 or body[k - 1] != '\\'):
            e = _match_close(body, k + 1, '(', ')')
            if e < 0:
                return None
            SUBS.append(body[k + 2:e]); k = e + 1
            continue
        if body[k] == '`' and (k == 0 or body[k - 1] != '\\'):
            e = body.find('`', k + 1)
            if e < 0:
                return None
            SUBS.append(body[k + 1:e]); k = e + 1
            continue
        out_chars.append(body[k]); k += 1
    return ''.join(out_chars)


def lex(cmd):
    """셸 한 줄을 (텍스트, 종류) 로 쪼갠다. 종류는 'w'(단어) / 'op' / 'st'(구조).

    인용을 지킨다 — 따옴표 안의 `|`·`&&`·`>` 는 그냥 글자다.
    히어독 본문은 통째로 건너뛴다. 본문의 `'`·`>`·`&&` 를 셸 문법으로 읽으면
    문서를 쓰는 흔한 명령이 전부 깨진다 (그리고 판정도 엉뚱해진다).
    """
    toks, buf, i, n = [], [], 0, len(cmd)
    pending_heredocs = []
    pending_st = []

    def flush():
        if buf:
            toks.append((''.join(buf), 'w'))
            del buf[:]
        while pending_st:
            toks.append((pending_st.pop(0), 'st'))

    while i < n:
        c = cmd[i]
        if c == '\\':
            if i + 1 < n and cmd[i + 1] == '\n':
                i += 2; continue        # 줄 이음 — 없는 것과 같다
            if i + 1 < n:
                buf.append(cmd[i + 1]); i += 2
            else:
                return None
            continue
        if c == "'":
            j = cmd.find("'", i + 1)
            if j < 0:
                return None
            buf.append(cmd[i + 1:j]); i = j + 1
            continue
        if c == '$' and i + 1 < n and cmd[i + 1] in ("'", '"'):
            q = cmd[i + 1]
            j, out = i + 2, []
            while j < n:
                if cmd[j] == '\\' and j + 1 < n:
                    out.append(cmd[j:j + 2]); j += 2; continue
                if cmd[j] == q:
                    break
                out.append(cmd[j]); j += 1
            if j >= n:
                return None
            body = ''.join(out)
            buf.append(_ansi_c(body) if q == "'" else body.replace('\\', ''))
            i = j + 1
            continue
        if c == '"':
            j, out = i + 1, []
            while j < n and cmd[j] != '"':
                if cmd[j] == '\\' and j + 1 < n:
                    out.append(cmd[j:j + 2]); j += 2
                    continue
                if cmd.startswith('$(', j):
                    e = _match_close(cmd, j + 1, '(', ')')
                    if e < 0:
                        return None
                    out.append(cmd[j:e + 1]); j = e + 1
                    continue
                if cmd[j] == '`':
                    e = cmd.find('`', j + 1)
                    if e < 0:
                        return None
                    out.append(cmd[j:e + 1]); j = e + 1
                    continue
                out.append(cmd[j]); j += 1
            if j >= n:
                return None
            body = ''.join(out)
            # bash 는 큰따옴표 안에서도 명령치환을 실행한다. 리터럴로만 보면
            # `echo "$(rm -rf .ai-bouncer)"` 가 단어 하나가 되어 모든 검사를 비껴간다.
            if _CMDSUB.search(body):
                lit = _strip_subs(body)
                if lit is None:
                    return None         # 안을 못 읽었다 — 판정 불가
                pending_st.append('$(')
                # 부분 치환도 자리표시를 남겨야 한다. `"$(echo docs)/x.txt"` 가
                # `/x.txt` 로 남으면 절대경로로 보여 스코프 밖으로 분류됐다.
                buf.append(SUB_TOKEN + re.sub(r'\\\\(.)', r'\\1', lit))
                i = j + 1
                continue
            buf.append(re.sub(r'\\(.)', r'\1', body)); i = j + 1
            continue
        if c == '\n' and pending_heredocs:
            # 히어독 본문을 종료어까지 건너뛴다
            flush(); toks.append(('\n', 'op'))
            i += 1
            for word, quoted in pending_heredocs:
                found = False
                while i < n:
                    e = cmd.find('\n', i)
                    line = cmd[i:e if e >= 0 else n]
                    i = (e + 1) if e >= 0 else n
                    if line.strip() == word:
                        found = True
                        break
                    if not quoted and _CMDSUB.search(line):
                        # 인용 안 된 히어독 본문의 치환은 실제로 실행된다
                        if _strip_subs(line) is None:
                            return None
                        pending_st.append('$(')
                if not found:
                    # 종료어가 없다. 끝까지 본문으로 삼키면 뒤 명령이 통째로
                    # 검사에서 사라진다 — 그건 fail-open 이다. 판정 불가로 둔다.
                    return None
            pending_heredocs = []
            continue
        if c in ' \t':
            flush(); i += 1
            continue
        # 산술 확장 `$(( … ))` / `$[ … ]` 은 명령을 실행하지 않는다.
        # 통째로 한 단어로 삼켜야 안쪽의 `<<`(좌시프트)를 히어독으로 오인하지 않고,
        # 순수 읽기인 `echo $((1+2))` 도 막지 않는다.
        ar = next((a for a in ARITH if cmd.startswith(a[0], i)), None)
        if ar:
            open_s, close_s = ar
            # `$(( $(( 1 )) ))` 처럼 중첩될 수 있다. 첫 `))` 로 닫으면 잉여
            # 괄호가 구조 토큰으로 남아 순수 읽기가 막힌다.
            oc, cc = open_s[-1], close_s[-1]
            depth = open_s.count(oc)
            j = i + len(open_s)
            while j < n and depth > 0:
                if cmd[j] == oc:
                    depth += 1
                elif cmd[j] == cc:
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            if depth > 0 or j >= n:
                return None             # 닫히지 않았다 — 판정 불가
            j = j - (len(close_s) - 1)
            inner = cmd[i + len(open_s):j]
            if _CMDSUB.search(inner):
                # 안에서 명령을 실행한다. 예전엔 표식만 남기고 버려서
                # `echo $(( 0 + $(rm -rf .ai-bouncer) ))` 가 통과했다.
                lit = _strip_subs(inner)
                if lit is None:
                    return None
                flush(); toks.append(('$(', 'st'))
            else:
                buf.append(cmd[i:j + len(close_s)])
            i = j + len(close_s)
            continue
        m = HEREDOC.match(cmd, i)
        if m:
            flush()
            j = m.end()
            q = ''
            if j < n and cmd[j] in '"\'':
                q = cmd[j]; j += 1
            # `<<\EOF` 나 `<<EO\F` 처럼 백슬래시로 인용할 수 있다.
            # bash 는 백슬래시를 지운 것을 종료어로 쓴다. 이걸 모르면 종료어가
            # 어긋나 뒤 명령이 통째로 본문으로 삼켜졌다.
            k, wchars = j, []
            while k < n:
                if cmd[k] == '\\' and k + 1 < n:
                    wchars.append(cmd[k + 1]); k += 2; continue
                if cmd[k].isalnum() or cmd[k] in '_-.':
                    wchars.append(cmd[k]); k += 1; continue
                break
            word = ''.join(wchars)
            if q and k < n and cmd[k] == q:
                k += 1
            if not word:
                return None            # 종료어를 못 읽었다 — 판정 불가
            # 종료어가 인용돼 있지 않으면 bash 는 본문에서 `$()`·백틱을 실행한다.
            # 본문을 통째로 건너뛰면 그 명령이 어떤 검사에도 안 닿는다.
            pending_heredocs.append((word, bool(q) or '\\' in cmd[j:k]))
            toks.append(('<<', 'op')); toks.append((word, 'heredoc'))
            i = k
            continue
        # 따옴표 밖 치환도 안쪽을 따로 떼어야 한다. 예전에는 `$(` 만 표식으로
        # 남기고 안쪽 토큰이 바깥 세그먼트에 섞여, `echo $(git push …)` 가
        # exe='echo' 로 읽혀 push 검사를 통째로 빠져나갔다.
        if cmd.startswith('$(', i) and not cmd.startswith('$((', i):
            e = _match_close(cmd, i + 1, '(', ')')
            if e < 0:
                return None
            # 자리표시를 남겨야 한다. 큰따옴표 분기에만 있고 여기 없어서
            # `rm -rf $(echo docs)` 는 인자가 통째로 사라져 통과했다.
            pending_st.append('$(')
            buf.append(SUB_TOKEN)
            SUBS.append(cmd[i + 2:e]); i = e + 1
            continue
        if cmd[i] == '`':
            e = cmd.find('`', i + 1)
            if e < 0:
                return None
            pending_st.append('`')
            buf.append(SUB_TOKEN)
            SUBS.append(cmd[i + 1:e]); i = e + 1
            continue
        if cmd.startswith('<(', i) or cmd.startswith('>(', i):
            e = _match_close(cmd, i + 1, '(', ')')
            if e < 0:
                return None
            pending_st.append(cmd[i:i + 2])
            buf.append(SUB_TOKEN)
            SUBS.append(cmd[i + 2:e]); i = e + 1
            continue
        hit = next((o for o in STRUCT if cmd.startswith(o, i)), None)
        # `{`/`}` 는 **홀로 선 경우**에만 셸 구조다. `-I{}` 처럼 단어에 붙으면
        # 그냥 글자다 — 쪼개면 xargs 의 -I 값이 다음 명령을 삼킨다.
        if hit in ('{', '}') and (buf or (i + 1 < n and cmd[i + 1] not in ' \t\n;&|')):
            buf.append(cmd[i]); i += 1
            continue
        if hit:
            flush(); toks.append((hit, 'st')); i += len(hit)
            continue
        hit = next((o for o in OPS if cmd.startswith(o, i)), None)
        if hit:
            if buf and ''.join(buf).isdigit() and hit[0] in '<>':
                del buf[:]
            flush(); toks.append((hit, 'op')); i += len(hit)
            continue
        buf.append(c); i += 1
    flush()
    return toks


def tokenize(cmd):
    return lex(cmd)


# 명령 안에서 `cd` 로 옮겨간 위치. 세그먼트를 순서대로 보며 갱신한다.
EFFECTIVE_CWD = ['']


def cwd_now():
    c = EFFECTIVE_CWD[0]
    return (CWD or PROJECT) if (not c or c == UNKNOWN_CWD) else c


def cwd_unknown():
    return EFFECTIVE_CWD[0] == UNKNOWN_CWD


UNKNOWN_CWD = '\x00?'


SUBSHELL_SEEN = [False]


def track_cd(exe, args, struct=()):
    """`cd <dir>` 세그먼트면 이후 상대경로의 기준을 옮긴다.

    `cd -` 는 어디로 가는지 모르고, 서브셸 `( cd x )` 의 이동은 밖으로 안 샌다.
    어느 쪽이든 "모른다"로 두고, 이후 상대경로 쓰기는 거부한다 —
    예전에는 `cd . && cd - && rm f` 가 통과했다.
    """
    if exe not in ('cd', 'pushd', 'popd'):
        return
    if struct or SUBSHELL_SEEN[0]:
        # 서브셸 `( cd x )` 의 이동은 밖에 영향이 없고,
        # `cd $(...)` 는 어디로 가는지 알 수 없다. 둘 다 "모름"이 안전하다.
        EFFECTIVE_CWD[0] = UNKNOWN_CWD
        return
    tgt = next((a for a in args if not a.startswith('-')), None)
    if exe == 'popd' or tgt is None or tgt == '-' or '-' in args:
        EFFECTIVE_CWD[0] = UNKNOWN_CWD
        return
    # 변수·치환이 섞이면 실제 경로를 알 수 없다. 계산해봐야 없는 경로가 나오고,
    # 그러면 이후 상대경로가 전부 "프로젝트 밖"이 되어 스코프가 통째로 꺼진다.
    if '$' in tgt or '`' in tgt or '*' in tgt or '?' in tgt:
        EFFECTIVE_CWD[0] = UNKNOWN_CWD
        return
    EFFECTIVE_CWD[0] = abspath(tgt)


def abspath(p):
    """토큰을 절대경로로 편다. 상대경로는 **세션 cwd** 기준이다.

    프로젝트 기준으로 붙이면 worktree 안에서 친 `src/a.js` 가 엉뚱한 곳을 가리켜,
    평범한 상대경로 작업이 전부 "worktree 밖"으로 오판됐다.
    링크도 여기서 푼다 — `/tmp` ↔ `/private/tmp` 나 `src/link -> ../.ai-bouncer`
    처럼 표기만 다른 같은 파일이 검사마다 다른 답을 내던 원인이다.
    """
    p = p.strip('"\'')
    if not p:
        return ''
    p = os.path.expanduser(p)           # `~/proj` 를 그대로 두면 프로젝트 밖으로 샌다
    base = p if os.path.isabs(p) else os.path.join(cwd_now(), p)
    # 상위는 항상 풀고, 마지막 성분도 **링크라면** 푼다.
    # 안 풀면 `ln -s ../.ai-bouncer/… src/s && echo x > src/s` 로 링크를 타고
    # 보호 대상을 덮어쓸 수 있다. 없는 파일은 그대로 둔다(새로 만드는 경우).
    head, tail = os.path.split(os.path.normpath(base))
    if not tail:
        return _real(base)
    full = os.path.normpath(os.path.join(_real(head) or head, tail))
    try:
        if os.path.islink(full):
            return _real(full)
    except (OSError, ValueError):
        pass
    return full


def norm(p):
    """프로젝트 기준 상대경로. 프로젝트 밖이면 절대경로 그대로.

    병렬 작업의 worktree 는 프로젝트의 사본이므로 worktree 기준으로도 상대화한다.
    안 그러면 worktree 안 모든 파일이 "프로젝트 밖"이 되어 edit_files 스코프가
    통째로 사라진다 — 사용자가 건 가드가 병렬에서만 조용히 없어졌다.
    """
    a = abspath(p)
    if not a:
        return '.'
    for root in (WORKTREE, PROJECT):
        if not root:
            continue
        if a == root:
            return '.'
        if a.startswith(root + '/'):
            return a[len(root) + 1:]
    return a


def glob_re(pat):
    i, o = 0, ['^']
    while i < len(pat):
        if pat.startswith('**/', i):
            o.append('(?:.*/)?'); i += 3
        elif pat.startswith('**', i):
            o.append('.*'); i += 2
        elif pat[i] == '*':
            o.append('[^/]*'); i += 1
        elif pat[i] == '?':
            o.append('[^/]'); i += 1
        else:
            o.append(re.escape(pat[i])); i += 1
    return re.compile(''.join(o) + '$')


def relative_and_unknown(p):
    """기준을 모르는 상태에서 상대경로를 쓰려 한다."""
    return cwd_unknown() and not os.path.isabs(p.strip('"\''))


def path_forbidden(p):
    """이 경로가 edit_files 스코프에 걸리는가. 뒤에 오는 패턴이 이긴다(`!` 는 예외).

    스코프는 프로젝트 안에서만 뜻이 있다. `**` 는 `^.*$` 라 절대경로까지 삼켜서,
    예전에는 `/tmp/scratch.txt` 조차 "스코프 안"이 되어 막혔다.
    """
    a = abspath(p)
    # 다른 작업의 worktree 는 그 작업의 스코프가 따로 있다. 여기서 확인할 수
    # 없으므로 손대지 못하게 한다 (병렬 작업 A 가 B 의 트리를 고치던 구멍).
    if a and '/.ai-bouncer/worktrees/' in a + '/' \
       and not (WORKTREE and (a == WORKTREE or a.startswith(WORKTREE + '/'))):
        return True
    rel = norm(p)
    if rel.startswith('/') or rel.startswith('../'):
        return False                    # 프로젝트 밖 — 이 스코프의 관심사가 아니다
    hit = False
    for pat in EDIT:
        neg = pat.startswith('!')
        body = pat[1:] if neg else pat
        # `!src/**` 는 "src 아래"만 뜻하지만 사용자는 src 자체도 포함해서 읽는다.
        # 그래야 `mkdir -p src`, `cp a src` 가 통한다.
        alt = body[:-3] if body.endswith('/**') else None
        if glob_re(body).match(rel) or (alt and glob_re(alt).match(rel)):
            hit = not neg
    return hit


FIRST_ARG_NOT_PATH = {'chmod', 'chown', 'chgrp'}
VALUE_FLAGS = {'truncate': {'-s', '--size'}, 'mkdir': {'-m', '--mode'},
               'split': {'-b', '-l', '-n', '-a', '--bytes', '--lines',
                         '--number', '--suffix-length'},
               'rsync': {'--exclude', '--include', '--exclude-from', '--include-from',
                         '-e', '--rsh', '--files-from', '--filter', '-f', '--chmod',
                         '--log-file', '--partial-dir', '--compare-dest', '--link-dest'},
               'install': {'-m', '-o', '-g', '--mode', '--owner', '--group'}}


def write_targets(exe, args):
    """이 명령이 실제로 **쓰는** 인자만 골라낸다."""
    vf, pos, i = VALUE_FLAGS.get(exe, set()), [], 0
    while i < len(args):
        a = args[i]
        if a in vf:
            i += 2; continue
        if not a.startswith('-') and a.strip('"\''):
            pos.append(a)
        i += 1
    # `--reference=X` 를 주면 첫 인자가 모드가 아니라 대상이다
    if exe in FIRST_ARG_NOT_PATH and pos \
       and not any(a.startswith('--reference') for a in args):
        pos = pos[1:]           # 첫 인자는 모드/소유자다 (755, u+w, ram:staff)
    mode = WRITERS[exe]
    if mode == 'all':
        return pos
    def _dest_dir(default):
        """`-C dir` / `--directory=dir` 로 목적지를 옮겼는가."""
        for i2, a in enumerate(args):
            # `patch -C` 는 --check(아무것도 안 씀), 디렉토리는 `-d` 다.
            dest_flags = ('-d', '--directory') if exe == 'patch' \
                else ('-C', '--directory', '-d', '--target-directory')
            if a in dest_flags and i2 + 1 < len(args):
                return [args[i2 + 1]]
            for pre in ('--directory=', '--target-directory=', '-C='):
                if a.startswith(pre):
                    return [a.split('=', 1)[1]]
        return default

    if mode == 'tar':
        first = args[0] if args else ''
        bundled = first if (first and not first.startswith('-')
                            and re.fullmatch(r'[a-zA-Z]+', first)) else ''
        letters = bundled + ''.join(
            a[1:] for a in args if a.startswith('-') and not a.startswith('--'))
        if 't' in letters or any(a in ('--list',) for a in args):
            return []                       # 목록 보기는 아무것도 안 쓴다
        if 'c' in letters or any(a in ('--create',) for a in args):
            # 아카이브 생성 — `-f <파일>` 에만 쓴다
            for i2, a in enumerate(args):
                if a == '-f' and i2 + 1 < len(args):
                    return [args[i2 + 1]]
                if a.startswith('--file='):
                    return [a.split('=', 1)[1]]
            # `-czf out.tgz` 처럼 묶인 형태 — 'f' 가 있으면 첫 위치인자가 아카이브다.
            # 대시 없는 옵션 묶음(`tar czf …`)은 위치인자에서 빼야 한다.
            rest = pos[1:] if (bundled and pos and pos[0] == bundled) else pos
            if 'f' in letters:
                return rest[:1]
            return []
        return _dest_dir(['.'])             # 추출은 cwd(또는 -C)에 쓴다
    if mode == 'prefix':
        # `split -b 1m IN PREFIX` — 마지막 위치인자가 접두사다 (없으면 cwd 의 x*)
        return pos[-1:] if len(pos) > 1 else ['.']
    if mode == 'cwd':
        if exe == 'patch' and any(a in ('-C', '--check', '--dry-run') for a in args):
            return []
        return _dest_dir(['.'])
    if mode == 'ln':
        # `ln -sf SRC` 는 cwd 에 basename(SRC) 를 만든다
        if len(pos) == 1:
            return [os.path.basename(pos[0].rstrip('/')) or '.']
        return pos[-1:]
    if mode == 'cp':
        # `cp -t <디렉토리> a b` 는 대상이 앞에 온다
        for i2, a in enumerate(args):
            if a in ('-t', '--target-directory') and i2 + 1 < len(args):
                return [args[i2 + 1]]
            if a.startswith('--target-directory='):
                return [a.split('=', 1)[1]]
        return pos[-1:] if len(pos) > 1 else []
    if exe == 'rsync' and any(a == '--dry-run' or (a.startswith('-') and not a.startswith('--')
                                                  and 'n' in a[1:]) for a in args):
        return []                       # dry-run 은 아무것도 안 쓴다
    if mode == 'last':
        return pos[-1:] if len(pos) > 1 else []      # 대상이 하나뿐이면 형태가 이상하다
    if mode == 'second':
        return pos[1:2]
    if mode == 'sed':
        return pos[1:] if any(a.startswith(('-i', '--in-place')) for a in args) else []
    if mode == 'dd':
        return [a.split('=', 1)[1] for a in args if a.startswith('of=')]
    # 플래그의 값만 쓴다
    hit = []
    long_forms = ('--output', '--output-document')
    for i, a in enumerate(args):
        if a == mode or a in long_forms:
            if i + 1 < len(args):
                hit.append(args[i + 1])
        elif a.startswith(mode + '=') or any(a.startswith(f + '=') for f in long_forms):
            hit.append(a.split('=', 1)[1])
        elif a.startswith(mode) and len(a) > len(mode):
            hit.append(a[len(mode):])       # `-oFILE` 처럼 값이 붙은 형태
    return hit


def split_segments(items):
    """연산자로 세그먼트를 나눈다. 각 세그먼트는 (텍스트, 종류) 목록이다."""
    cur, res = [], []
    for text, kind in items:
        # `)` 는 case 패턴의 끝이자 서브셸의 끝이다. 구분하지 않으면
        # `case x in x) git push;; esac` 의 push 가 앞 토큰들에 묻힌다.
        if (kind == 'op' and text in SEPARATOR_BASE) or (kind == 'st' and text in ('(', ')')):
            if cur:
                res.append(cur)
            cur = []
        else:
            cur.append((text, kind))
    if cur:
        res.append(cur)
    return res


def parse_redirects(seg):
    """세그먼트를 (명령 단어들, [(연산자, 대상)], 구조토큰들) 로 가른다.

    fd 번호는 렉서가 이미 붙여 처리했다.
    """
    clean, redirs, struct, i = [], [], [], 0
    while i < len(seg):
        text, kind = seg[i]
        if kind == 'heredoc':
            i += 1
            continue
        if kind == 'op' and text == '<<':
            i += 1
            continue
        if kind == 'op' and REDIR.match(text):
            tgt = seg[i + 1][0] if i + 1 < len(seg) else ''
            redirs.append((text, tgt))
            i += 2
            continue
        if kind == 'st':
            struct.append(text)
        else:
            clean.append(text)
        i += 1
    return clean, redirs, struct


ASSIGN = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*=')


def exe_is_substitution(seg, struct):
    """명령 이름 자리를 치환이 차지했는가.

    `"$(echo git)" push` 는 자리표시가, `$(echo git) push` 는 아예 아무것도
    안 남아 뒤따르는 `push` 가 실행 파일로 읽혔다. 둘 다 판정 불가다.
    """
    seen_word = False
    for text, kind in seg:
        if kind == 'st':
            # 마커는 앞선 단어에 딸린 것이다. 단어가 하나도 없이 먼저 나오면
            # 치환 자체가 명령 이름이다 (`$(echo git) push`).
            if seen_word:
                return False
            return text in ('$(', '`')
        if kind == 'w':
            t = text.strip('"\'')
            if ASSIGN.match(t):
                seen_word = True
                continue                   # `X=…` 접두는 명령이 아니다
            return t.startswith(SUB_TOKEN)
    return False


def resolve_exe(seg):
    """(실행 파일 이름, 그 지점부터의 토큰, 환경변수 이름들) 을 돌려준다.

    `X=1 env nohup nice -n 5 git push` 처럼 접두가 겹겹이 붙어도 진짜 명령까지 벗겨낸다.
    """
    env, i, last = [], 0, ''
    while i < len(seg):
        raw = seg[i].strip('"\'').lstrip('\\')
        # 환경변수 접두. 값에 `/` 가 있는지로 가르면 `FOO=/tmp cp …` 가
        # 접두로 인식되지 않고 basename('FOO=/tmp')='tmp' 가 명령이 돼 빠져나간다.
        if ASSIGN.match(raw):
            env.append(raw.split('=', 1)[0])
            i += 1
            continue
        base = os.path.basename(raw)
        # `if`/`then`/`do` 뒤에 오는 것이 진짜 명령이다. 키워드를 실행 파일로
        # 읽으면 `if true; then git push; fi` 가 무검사로 통과한다.
        if base in SKIP_KEYWORDS:
            i += 1
            continue
        last = base
        head_flags = []
        for a in seg[i + 1:]:
            if not a.startswith('-'):
                break
            head_flags.append(a)
        if base == 'env' and any(a == '-S' or a.startswith('--split-string')
                                 or (a.startswith('-S') and len(a) > 2) for a in head_flags):
            # `env -S "…"` 는 문자열 하나가 통째로 명령이다. 안을 판정할 수 없다.
            return 'env -S', seg[i:], env
        if base in WRAPPERS:
            # `command -v foo` / `type -p foo` 는 조회다. 단 그 플래그가
            # **첫 비플래그 토큰보다 앞에** 있을 때만 — 아니면 `command cp -v a b`
            # 의 cp 를 안 보게 된다.
            if base in ('command', 'type'):
                head = []
                for a in seg[i + 1:]:
                    if not a.startswith('-'):
                        break
                    head.append(a)
                # `-p` 는 조회가 아니라 "기본 PATH로 실행"이다. 조회는 -v/-V 뿐.
                if any(a in ('-v', '-V') for a in head):
                    return base, seg[i:], env
            j, vals = i + 1, WRAPPER_VALUE_FLAGS[base]
            while j < len(seg):
                a = seg[j]
                if a in vals:
                    j += 2; continue
                if a.startswith('-'):
                    j += 1; continue
                if base == 'timeout' and DURATION.match(a):
                    j += 1; continue        # `timeout 5 cmd` 의 5
                break
            if j >= len(seg):               # 래퍼만 있고 뒤에 명령이 없다
                return base, seg[i:], env
            i = j
            continue
        return base, seg[i:], env
    return last, seg[i:] if i < len(seg) else [], env


def inline_program(exe, cmd):
    """인라인 코드를 실행하는 형태인가 (`sh -c …`, `python3 -c …`)."""
    return exe in INTERPRETERS and any(
        a in INLINE_FLAGS or a.startswith(INLINE_FLAGS) for a in cmd[1:])


def git_sub(cmd):
    """git 의 전역 옵션을 건너뛰고 서브커맨드를 찾는다. `-c` 는 판정 불가."""
    i = 1
    while i < len(cmd):
        t = cmd[i]
        if t in ('-C', '--git-dir', '--work-tree', '--namespace', '--exec-path'):
            i += 2
            continue
        # `-c` 와 동등물. 별칭을 심어 push 를 숨길 수 있다.
        if t == '-c' or t.startswith('--config-env'):
            return None
        if t.startswith('-'):
            i += 1
            continue
        # 서브커맨드 자리에 변수·치환이 오면 무엇인지 알 수 없다
        if '$' in t or '`' in t or SUB_TOKEN in t:
            return None
        return t
    return ''


def awk_writes(prog):
    """awk 프로그램이 파일을 쓰거나 명령을 실행하는가.

    `$3 > 500` 같은 비교와 `print $1 > f` 를 갈라야 한다. 리다이렉트는 항상
    출력 목록 뒤에 오므로, `>` 앞쪽 같은 문장 안에 print/printf 가 있으면 쓰기로 본다.
    대상이 변수여도 잡힌다 — 대상 모양을 보지 않기 때문이다.
    """
    if AWK_EXEC.search(prog):
        return True
    if '>>' in prog:
        return True
    for m in re.finditer(r'>', prog):
        s, e = m.start(), m.end()
        if prog[s - 1:s] == '>' or prog[e:e + 1] in ('=', '>'):
            continue                    # >= 나 >> 의 일부
        head = AWK_STMT_SPLIT.split(prog[:s])[-1]
        # 괄호가 열려 있으면 표현식 안이다 — `print ($1 > 5)` 는 비교다.
        if head.count('(') > head.count(')'):
            continue
        if re.search(r'\bprintf?\b', head):
            return True
    return False


def _has_component(parts, want):
    n = len(want)
    for i in range(len(parts) - n + 1):
        if tuple(parts[i:i + n]) == want:
            return i
    return -1


def is_engine_path(tok):
    """이 토큰이 엔진 소유 경로를 가리키는가. 성분 단위로 본다.

    심볼릭 링크를 먼저 푼다 — `.ai-bouncer/worktrees/x -> ../tasks` 로 만들면
    worktrees 예외를 타고 상태 파일을 그대로 덮어쓸 수 있었다.
    worktrees 예외는 **그 지점까지의 접두에만** 적용한다. 뒤에 다시 엔진 성분이
    나오면(worktree 안의 .claude/ai-bouncer/) 그건 여전히 엔진 파일이다.
    """
    a = abspath(tok)
    roots = [r for r in (PROJECT, WORKTREE) if r]
    # `cd /tmp && rm -rf .ai-bouncer` 는 우리 것이 아니다. 프로젝트 밖의
    # 동명 디렉토리까지 막으면 근거 없는 차단이 된다.
    if a and roots and not any(a == r or a.startswith(r + '/') for r in roots):
        return False
    p = norm(tok).replace('\\', '/')
    parts = p.split('/')
    if len(parts) >= 2 and tuple(parts[-2:]) == ENGINE_SETTINGS:
        return True
    # `.claude` 를 통째로 지우면 엔진·설정이 전부 사라진다. 부모 디렉토리 자체를 막는다.
    if parts and parts[-1] in ENGINE_PARENTS and not p.startswith('/'):
        return True
    if parts[-1] in ENGINE_FILES:
        return True
    for want in ENGINE_EXEMPT:
        i = _has_component(parts, want)
        if i >= 0:
            # 예외 지점 뒤쪽만 다시 본다 (worktree 안의 설정 디렉토리는 보호 대상)
            parts = parts[i + len(want):]
            break
    for want in ENGINE_DIRS:
        if _has_component(parts, want) >= 0:
            return True
    return False


GLOB_CHARS = set('*?[')


def glob_could_hit_engine(tok):
    """`rm -rf .ai*` 처럼 글로브가 엔진 디렉토리를 삼킬 수 있는가.

    글로브는 셸이 풀기 때문에 우리는 확장 결과를 못 본다. 리터럴 접두가
    엔진 디렉토리 이름의 접두이기만 해도 삼킬 수 있으므로 거부한다.
    """
    t = tok.strip('"\'').replace('\\', '/')
    if not (set(t) & GLOB_CHARS):
        return False
    # 접두 문자열 비교로는 `.claude/*` 를 못 잡았다 (`ai-bouncer` 는 점이 없다).
    # 글로브를 정규식으로 바꿔 엔진 경로와 그 조상에 실제로 맞는지 본다.
    rel = norm(t)
    try:
        rx = glob_re(rel)
    except re.error:
        return True                     # 판정 못 하면 막는다
    targets = ['.ai-bouncer', '.claude', '.claude/ai-bouncer']
    return any(rx.match(x) for x in targets)


def reset_cwd():
    """판정 패스를 새로 시작할 때 cd 추적을 초기화한다.

    EDIT 패스 마지막 세그먼트의 `cd` 가 PUSH 패스 첫 세그먼트로 새어,
    `touch src/a.js && cd -` 처럼 **쓰기보다 뒤에 오는 cd** 가 앞을 막았다.
    """
    EFFECTIVE_CWD[0] = ''


def check_engine_files(segments):
    """엔진 파일은 어느 스테이지에서도 직접 **수정**할 수 없다.

    세그먼트마다 따로 본다. 줄 전체의 첫 토큰이 bouncer 인지로 면제하면
    `bouncer status && echo x > state.json` 이 통째로 빠져나간다.
    """
    reset_cwd()
    SUBSHELL_SEEN[0] = any(k == 'st' and t in ('(', ')')
                           for seg in segments for t, k in seg)
    for seg in segments:
        clean, redirs, struct = parse_redirects(seg)
        # 리다이렉트 대상은 bouncer 자신의 명령이라도 검사한다.
        # (`bouncer.sh > .ai-bouncer/tasks/x/state.json` 으로 상태를 덮어썼다)
        for op, tgt in redirs:
            if op != '<' and is_engine_path(tgt):
                out(ENGINE_MSG)
        exe, cmd, _ = resolve_exe(clean)
        if cmd and is_bouncer(cmd[0]):
            continue
        if SUB_TOKEN in exe:
            out(SUB_EXE_MSG)
        if exe in OPAQUE_EXE:
            out(OPAQUE_MSG % exe)
        # `git clean -fdx` 는 gitignore된 것을 지운다 — 상태 디렉토리가 정확히 그것이다.
        if exe == 'git' and git_sub(cmd) == 'clean' \
           and not any(a in ('-n', '--dry-run') or (a.startswith('-') and not a.startswith('--')
                                                    and 'n' in a[1:]) for a in cmd[1:]):
            out("`git clean` 은 무시 대상(.ai-bouncer/ 상태 포함)을 지운다.\n"
                "진행 중인 작업이 통째로 사라지므로 허용되지 않는다.\n"
                "정말 필요하면 `bouncer cancel` 로 작업을 끝낸 뒤에 해라.")
        # 읽기 명령은 글로브가 엔진 디렉토리를 훑어도 아무것도 안 바꾼다
        for t in ([] if exe in ENGINE_READ_OK else clean):
            if glob_could_hit_engine(t):
                out("`%s` 는 글로브라 엔진 디렉토리(.ai-bouncer/ 등)를 삼킬 수 있다.\n"
                    "지울 대상을 정확히 적어라." % t)
        # `rm -rf .ai-bounce{r,x}` — 중괄호 확장은 셸이 푼다. 무엇이 될지 모른다.
        if struct and any(t in ('{', '}') for t in struct) and exe not in ENGINE_READ_OK:
            for t in clean:
                n2 = norm(t).rsplit('/', 1)[-1]
                if n2 and any(c.startswith(n2) for w in ENGINE_DIRS for c in w):
                    out("중괄호 확장(`%s{…}`)은 무엇이 펼쳐질지 확인할 수 없다.\n"
                        "엔진 디렉토리를 삼킬 수 있어 허용되지 않는다. 대상을 정확히 적어라." % t)
        if exe == 'find' and any(a in ('-delete', '-exec', '-execdir', '-ok', '-okdir')
                                 for a in cmd[1:]):
            # `find . -name state.json -delete` 로 상태 파일이 사라졌다
            out("`find -exec/-delete` 로는 무엇을 지울지 확인할 수 없어 허용되지 않는다.")
        # `python3 -c "open('.ai-bouncer/state.json','w')"` — 코드 문자열 안의 경로는
        # 성분으로 안 보인다. 엔진 표식이 들어 있으면 통째로 거부한다.
        if exe in INLINE_CODE_EXE:
            for a in cmd[1:]:
                if any(m in a for m in ENGINE_MARKERS):
                    out(ENGINE_MSG)
        if exe == 'git' and not git_read_error(cmd):
            continue                    # `git log -- .ai-bouncer` 같은 이력 조회
        if exe in ENGINE_READ_OK:
            continue                    # 읽기는 자유
        if any(is_engine_path(t) for t in clean):
            out(ENGINE_MSG)
        track_cd(exe, cmd[1:], struct)


SINK_OK = {'/dev/null', '/dev/stdout', '/dev/stderr', '/dev/tty'}


def redirect_writes(op, tgt):
    """이 리다이렉트가 실제로 파일을 만드는가."""
    if op in ('<', '<<<'):
        return False                    # 입력·히어스트링은 아무것도 쓰지 않는다
    if op == '>&' and tgt.isdigit():
        return False                    # 2>&1 같은 fd 복제
    return tgt not in SINK_OK


def outside_worktree(p):
    """작업 트리가 worktree인데 메인 레포 쪽 경로를 건드리는가."""
    if not WORKTREE or not PROJECT:
        return False
    full = abspath(p)
    if not full:
        return False
    return (full == PROJECT or full.startswith(PROJECT + '/')) \
        and full != WORKTREE and not full.startswith(WORKTREE + '/')


def check_outside(seg_tokens, redirs, exe, args):
    """worktree 작업 중 메인 레포를 고치면 검증이 다른 트리를 본다."""
    if not WORKTREE:
        return
    if cwd_unknown():
        for op, t in redirs:
            if redirect_writes(op, t) and not os.path.isabs(t.strip('"\'')):
                out("`cd` 대상이 리터럴이 아니라 기준 디렉토리를 알 수 없다.\n"
                    "worktree 안인지 확인할 수 없으므로 절대경로로 적어라: %s" % t)
        if exe in WRITERS:
            for a in write_targets(exe, args):
                if not os.path.isabs(a.strip('"\'')):
                    out("`cd` 대상이 리터럴이 아니라 기준 디렉토리를 알 수 없다.\n"
                        "worktree 안인지 확인할 수 없으므로 절대경로로 적어라: %s" % a)
    bad = [t for op, t in redirs if redirect_writes(op, t) and outside_worktree(t)]
    if exe in WRITERS:
        bad += [a for a in write_targets(exe, args) if outside_worktree(a)]

    if bad:
        out("이 작업은 별도 worktree에서 진행 중이다:\n    %s\n"
            "그 밖을 건드리려 한다: %s\n\n"
            "여기서 고치면 검증과 finalize는 손대지 않은 worktree를 보고 전부 통과한다.\n"
            "worktree 안의 같은 파일을 고쳐라." % (WORKTREE, bad[0]))


def check_redirects(redirs):
    for op, tgt in redirs:
        if redirect_writes(op, tgt):
            out("이 단계는 읽기 전용이다. 파일로 출력을 보낼 수 없다: %s %s" % (op, tgt))


def check_env(env, readonly):
    for name in env:
        if readonly:
            if name in ENV_SAFE or name.startswith('LC_'):
                continue
            out("이 단계는 읽기 전용이다. 환경변수 접두(`%s=…`)는 무엇을 실행할지 "
                "판정할 수 없어 허용되지 않는다." % name)
        if name in ENV_DANGEROUS or name in ENV_DANGEROUS_EXACT \
           or name.startswith(ENV_DANGEROUS_PREFIX):
            out("`%s=…` 는 실행할 명령 자체를 바꿀 수 있어 이 단계에서는 허용되지 않는다."
                % name)


def git_read_error(cmd):
    """읽기가 아니면 사유 문자열, 읽기면 None."""
    sub = git_sub(cmd)
    if sub is None:
        return ("`git -c …` 는 무엇을 하는지 판정할 수 없다(별칭 주입 가능). 허용되지 않는다.")
    if sub == '':
        return None                     # `git` 만 치면 도움말
    if sub == 'grep' and any(a.startswith(('-O', '--open-files-in-pager')) for a in cmd):
        return ("`git grep -O` 는 매치된 파일을 임의 명령에 넘겨 실행한다. "
                "허용되지 않는다.")
    if sub in GIT_READ:
        return None
    # `git apply --check`, `git push --dry-run` 처럼 아무것도 안 바꾸는 형태
    if git_safe_form(sub, cmd):
        return None
    if sub == 'clean':
        if any(a.startswith('-') and not a.startswith('--') and 'n' in a[1:] for a in cmd):
            return None
        return "`git clean` 은 파일을 지운다. 확인만 하려면 `-n` 을 붙여라."
    if sub not in GIT_SUB:
        return ("`git %s` 는 읽기 명령이 아니다. 이 단계에서는 허용되지 않는다." % sub)
    rule = GIT_SUB[sub]
    after = cmd[cmd.index(sub) + 1:]
    pos = [a for a in after if not a.startswith('-')]
    flags = [a for a in after if a.startswith('-')]
    for f in flags:
        head = f.split('=', 1)[0]
        if head in rule['bad']:
            return ("`git %s %s` 는 쓰기 동작이다. 이 단계에서는 허용되지 않는다." % (sub, f))
    if not pos:
        if rule['bare_ok']:
            return None
        return ("`git %s` 는 이 형태로는 읽기가 아니다. 허용: %s"
            % (sub, ', '.join(sorted(rule['first']))))
    if rule['first'] is not None and pos[0] not in rule['first']:
        return ("`git %s %s` 는 읽기가 아니다. 허용: %s"
            % (sub, pos[0], ', '.join(sorted(rule['first']))))
    # 목록 플래그가 있으면 위치인자는 패턴이다 (`git branch --list 'feat*'`).
    limit = rule['max_pos']
    if rule.get('list_flags') and any(f.split('=', 1)[0] in rule['list_flags']
                                     for f in flags):
        limit = max(limit, 1)
    if len(pos) > limit:
        return ("`git %s` 에 인자를 %d개 주면 쓰기 동작이다 (읽기는 최대 %d개)."
            % (sub, len(pos), limit))

    return None


SUB_EXE_MSG = ("명령 이름 자리에 치환이 있어 무엇을 실행하는지 판정할 수 없다.\n"
               "값을 먼저 구해서 명령을 그대로 적어라.")
OPAQUE_MSG = ("`%s` 는 인자가 곧 실행할 코드라 무엇을 하는지 판정할 수 없다.\n"
              "명령을 그대로 적어라.")


def check_readonly_cmd(exe, cmd):
    if cmd and is_bouncer(cmd[0]):
        return
    if exe in OPAQUE_EXE:
        out(OPAQUE_MSG % exe)
    if exe == 'env -S':
        out("`env -S \"…\"` 는 문자열 하나가 통째로 명령이라 판정할 수 없다.\n"
            "명령을 그대로 적어라.")
    if exe in SHELL_KEYWORDS:
        out("이 단계는 읽기 전용이다. `%s` 같은 복합 구문은 안을 확인할 수 없어\n"
            "허용되지 않는다. 조회는 한 줄 명령으로 해라." % exe)
    if SUB_TOKEN in exe:
        out(SUB_EXE_MSG)
    if exe not in READ_ONLY:
        out("이 단계는 읽기 전용이다. `%s` 는 파일을 쓸 수 있어 허용되지 않는다.\n"
            "읽기·검색은 가능하고, 검증 명령은 `bouncer run <step-id>` 로 실행한다." % exe)
    args = cmd[1:]
    spec = WRITE_FLAG_CMD.get(exe, {'exact': set(), 'prefix': ()})
    short = spec.get('inshort')
    for a in args:
        # `-ni.bak` 처럼 다른 단축 플래그와 묶여 오는 형태도 잡아야 한다
        # 선행 알파벳 묶음만 플래그다. 값까지 훑으면 `-es/main/x/` 의 'i' 에 걸린다.
        mm = re.match(r'-([a-zA-Z]+)', a) if a.startswith('-') and not a.startswith('--') else None
        combined = bool(short and mm and short in mm.group(1))
        if a in WRITE_FLAG_ANY or a.startswith(WRITE_PREFIX_ANY) \
           or a in spec['exact'] or (spec['prefix'] and a.startswith(spec['prefix'])) \
           or combined:
            out("`%s %s` 는 파일을 쓴다. 이 단계에서는 허용되지 않는다." % (exe, a))
    if exe in POSITIONAL_OUT:
        value_flags, pos, i = POSITIONAL_OUT[exe], 0, 0
        while i < len(args):
            a = args[i]
            if a in value_flags:
                i += 2
                continue
            if a.startswith('-'):
                i += 1
                continue
            pos += 1
            i += 1
        if pos > 1:
            out("`%s <입력> <출력>` 은 두 번째 인자를 파일로 쓴다. 출력 인자를 빼라." % exe)
    if exe == 'sed':
        if any(a in ('-f', '--file') or a.startswith('--file=') for a in args):
            out("`sed -f <파일>` 은 스크립트를 확인할 수 없어 허용되지 않는다.")
        for a in args:
            if a.startswith('--expression=') and sed_writes(a.split('=', 1)[1]):
                out("sed 스크립트의 `w` 명령은 파일을 쓴다. 이 단계에서는 허용되지 않는다.")
        # 따옴표로 묶인 스크립트(`'1w out'`)와 공백으로 갈라진 형태(`1w out`) 둘 다 본다.
        if any(sed_writes(a) for a in args if not a.startswith('-')) \
           or any(SED_W_SPLIT.match(a) for a in args[:-1]):
            out("sed 스크립트의 `w` 명령은 파일을 쓴다. 이 단계에서는 허용되지 않는다.")
    if exe in AWK_EXES:
        if any(a in ('-f', '--file', '--source') or a.startswith('--file=') for a in args):
            out("`awk -f <파일>` 은 프로그램을 확인할 수 없어 허용되지 않는다.")
        for a in args:
            if not a.startswith('-') and awk_writes(a):
                out("이 awk 프로그램은 파일을 쓰거나 명령을 실행할 수 있다: %s" % a[:60])
    if exe == 'tar':
        # `-` 로 시작하는 인자만 옵션이다. 파일 이름에서 앞 글자를 뽑으면
        # `tar xf t.tar` 의 `t` 가 목록 플래그로 오인돼 추출이 통과했다.
        opt_args = [a for a in args if a.startswith('-') and not a.startswith('--')]
        # `tar tf x.tar` 처럼 대시 없는 묶음도 전통적 옵션이다. 단 tar 옵션
        # 글자로만 이뤄진 **첫** 인자일 때만 — 파일 이름을 옵션으로 읽으면 안 된다.
        if args and not args[0].startswith('-') and re.fullmatch(r'[a-zA-Z]+', args[0]) \
           and set(args[0]) <= set('ctxurdAtfvzjJZphmOWSPkKUlL'):
            opt_args.insert(0, '-' + args[0])
        mm = [re.match(r'-([a-zA-Z]+)', a) for a in opt_args]
        letters = ''.join(m.group(1) for m in mm if m)
        if any(a.startswith('--to-command') for a in args):
            out("`tar --to-command` 은 임의 명령을 실행한다. 허용되지 않는다.")
        if not ('t' in letters or any(a in ('--list', '--test-label') for a in args)):
            out("`tar` 는 목록 보기(`-t`) 외에는 파일을 쓴다. 이 단계에서는 허용되지 않는다.")
    if exe == 'find' and any(a in ('-exec', '-execdir', '-delete', '-ok', '-okdir')
                             for a in args):
        out("`find -exec/-delete` 는 임의 명령을 실행한다. 이 단계에서는 허용되지 않는다.")
    if exe == 'git':
        err = git_read_error(cmd)
        if err:
            out(err)


def check_push_cmd(exe, cmd, struct=()):
    if SUB_TOKEN in exe:
        out(SUB_EXE_MSG)
    if exe in OPAQUE_EXE:
        out(OPAQUE_MSG % exe)
    if exe == 'env -S':
        out("`env -S \"…\"` 는 문자열 하나가 통째로 명령이라 판정할 수 없다.")
    # 명령치환이 섞였는데 서브커맨드가 아는 것이 아니면, 치환이 그 자리를
    # 차지했다는 뜻이다 (`git $(echo push) origin main`).
    if exe == 'git' and struct:
        _sub = git_sub(cmd)
        if _sub is None or (_sub and _sub not in KNOWN_GIT_SUBS):
            out("git 서브커맨드 자리에 명령 치환(`$(…)`)이 있어 판정할 수 없다.\n"
                "이 단계에서는 서브커맨드를 그대로 적어야 한다.")
    # `git $x`, `git $(echo push)` — 서브커맨드 자리를 가리면 판정할 수 없다.
    # 인자에 치환이 있는 것 자체는 문제가 아니다 (`git commit -m "$(cat msg)"`).
    if exe == 'git' and not git_sub(cmd) \
       and any('$' in a or '`' in a for a in cmd[1:]):
        out("git 서브커맨드 자리에 변수·명령 치환이 있어 무엇을 하는지 판정할 수 없다.\n"
            "이 단계에서는 서브커맨드를 그대로 적어야 한다.")
    if exe == 'git-push':
        out("push가 차단되었다.")
    if inline_program(exe, cmd):
        out("`%s -c …` 안의 코드는 확인할 수 없다 (push를 숨길 수 있다).\n"
            "스크립트 파일로 만들어 실행하거나, 명령을 직접 써라." % exe)
    # `--no-push`, `[].push`, `/push/{print}` 같은 정상 인자를 잡지 않도록
    # `git push` 형태만 본다.
    if exe in ('awk', 'gawk', 'python', 'python3', 'perl', 'ruby', 'node', 'sh', 'bash') \
       and any(re.search(r'\bgit\b[^\n;|&]*\bpush\b', a) for a in cmd[1:]):
        out("인터프리터·셸을 통한 push 시도로 보인다. 이 단계에서는 허용되지 않는다.")
    if exe != 'git':
        return
    sub = git_sub(cmd)
    if sub is None:
        out("`git -c …` 는 별칭으로 push를 숨길 수 있어 이 단계에서는 허용되지 않는다.")
    if sub in GIT_PUSH_SUBS:
        if sub == 'push' and any(a in ('-n', '--dry-run') for a in cmd):
            return                      # 아무것도 보내지 않는다
        out("push가 차단되었다.")
    if sub == 'subtree' and 'push' in cmd:
        out("push가 차단되었다.")
    if sub == 'config' and any('alias.' in a for a in cmd):
        out("이 단계에서 git 별칭을 등록할 수 없다 (push를 숨길 수 있다).")


if CHECK_PATH:
    # 셸 `case` 로 따로 보던 것을 여기로 모았다. 거긴 정규화를 안 해서
    # `…/worktrees/../tasks/x/state.json` 이 예외를 타고 통과했다.
    if is_engine_path(TARGET):
        sys.stdout.write(ENGINE_MSG)
    elif outside_worktree(TARGET):
        sys.stdout.write(
            "이 작업은 별도 worktree에서 진행 중이다:\n    %s\n"
            "그 밖의 파일을 고치려 한다: %s\n\n"
            "여기서 고치면 검증과 finalize는 손대지 않은 worktree를 보고 전부 통과한다.\n"
            "worktree 안의 같은 파일을 고쳐라. 셸도 그 안에서 실행한다:\n    cd %s"
            % (WORKTREE, TARGET, WORKTREE))
    elif EDIT is not None and (EDIT is True or path_forbidden(TARGET)):
        sys.stdout.write("파일 수정이 차단되었다: %s" % norm(TARGET))
    sys.exit(0)

TOKENS = tokenize(CMD)
if TOKENS is None:
    out("따옴표가 닫히지 않아 명령을 판정할 수 없다.")

SEGMENTS = split_segments(TOKENS)
# 치환 안쪽을 같은 규칙으로 본다. 바깥 토큰 스트림에 끼워 넣으면
# 바깥 명령이 인자를 잃으므로, **별도 세그먼트**로 덧붙인다.
_work, _seen = list(SUBS), set()
SUB_SEGMENTS = []
while _work:
    _sub = _work.pop(0)          # 원본 순서. LIFO 로 처리하면 뒤쪽 치환의
                                 # `cd` 가 앞쪽 치환보다 먼저 반영됐다
    if not _sub.strip() or _sub in _seen:
        continue
    if len(_seen) > 64:
        out("명령 치환이 너무 많아 전부 판정할 수 없다. 명령을 나눠서 실행해라.")
    _seen.add(_sub)
    del SUBS[:]
    _t = lex(_sub)
    if _t is None:
        out("명령 치환 안을 판정할 수 없다. 값을 먼저 구해서 명령을 그대로 적어라.")
    SUB_SEGMENTS.append(split_segments(_t))
    _work.extend(SUBS)
check_engine_files(SEGMENTS)
for _segs in SUB_SEGMENTS:
    check_engine_files(_segs)

def run_passes(SEGMENTS, TOKENS):
    """한 명령(또는 치환 하나)에 대해 모든 검사를 돌린다."""
    reset_cwd()
    # 세그먼트를 `(`/`)` 로도 나누므로 서브셸 표식이 세그먼트 안에 안 남는다.
    # 명령 전체 기준으로 기억해둔다.
    SUBSHELL_SEEN[0] = any(k == 'st' and t in ('(', ')') for t, k in TOKENS)
    if EDIT is True:
        # ── 전면 읽기 전용 스테이지 (`edit_files: true`) ──────────
        bad = sorted({t for t, k in TOKENS if k == 'st'})
        if bad:
            out("이 단계는 읽기 전용이다. 안을 확인할 수 없는 구문(%s)은 쓸 수 없다.\n"
                "검증 명령을 돌려야 하면 `bouncer run <step-id>` 를 써라." % ' '.join(bad))
        for seg in SEGMENTS:
            clean, redirs, struct = parse_redirects(seg)
            check_redirects(redirs)
            if not clean:
                continue
            exe, cmd, env = resolve_exe(clean)
            if exe_is_substitution(seg, struct):
                out("명령 이름 자리에 치환이 있어 무엇을 실행하는지 판정할 수 없다.\n"
                    "값을 먼저 구해서 명령을 그대로 적어라.")
            check_env(env, True)
            check_outside(clean, redirs, exe, cmd[1:])
            if exe:
                check_readonly_cmd(exe, cmd)
            track_cd(exe, cmd[1:], struct)

    elif EDIT is not None:
        # ── 경로 스코프 스테이지 (`edit_files: [글로브…]`) ─────────
        # `!` 예외는 "여기는 써도 된다"는 뜻이다. 임의 명령은 허용하되
        # 스코프에 걸린 경로에 **쓰는 것만** 막는다.
        for seg in SEGMENTS:
            clean, redirs, struct = parse_redirects(seg)
            for op, tgt in redirs:
                # /dev/null 과 fd 복제까지 막으면 `npm test 2>&1` 조차 안 돈다.
                if redirect_writes(op, tgt):
                    if relative_and_unknown(tgt):
                        out("`cd -` / 서브셸 이동 뒤라 `%s` 가 어느 디렉토리인지 알 수 없다." % tgt)
                    if path_forbidden(tgt):
                        out("이 단계에서 %s 에 쓸 수 없다." % tgt)
            if not clean:
                continue
            exe, cmd, env = resolve_exe(clean)
            if exe_is_substitution(seg, struct):
                out("명령 이름 자리에 치환이 있어 무엇을 실행하는지 판정할 수 없다.\n"
                    "값을 먼저 구해서 명령을 그대로 적어라.")
            check_env(env, False)
            check_outside(clean, redirs, exe, cmd[1:])
            if not is_bouncer(cmd[0] if cmd else ''):
                for t in clean:
                    if is_engine_path(t):
                        out(ENGINE_MSG)
            if exe == 'env -S':
                out("`env -S \"…\"` 는 문자열 하나가 통째로 명령이라 판정할 수 없다.")
            if exe in OPAQUE_EXE:
                out(OPAQUE_MSG % exe)
            if inline_program(exe, cmd):
                out("`%s -c …` 안의 코드는 확인할 수 없어 이 단계에서는 허용되지 않는다.\n"
                    "스크립트 파일로 만들어 실행하거나, 명령을 직접 써라." % exe)
            args = cmd[1:]
            if exe == 'git':
                sub = git_sub(cmd)
                ok_form = git_safe_form(sub, cmd)
                # `git checkout -- src/a.js` / `git restore src/a.js` 처럼 경로를
                # 명시하면 그 경로만 본다. 스코프가 열어준 곳은 되돌릴 수 있어야 한다.
                if not ok_form and sub in ('checkout', 'restore'):
                    if '--' in cmd:
                        paths = cmd[cmd.index('--') + 1:]
                    elif sub == 'restore':
                        paths = [a for a in cmd[cmd.index(sub) + 1:] if not a.startswith('-')]
                    else:
                        paths = []
                    ok_form = bool(paths) and not any(path_forbidden(a) for a in paths)
                if sub in GIT_TREE_WRITE and not ok_form and git_read_error(cmd):
                    out("`git %s` 는 워킹트리를 바꾼다. 이 단계에서는 허용되지 않는다.\n"
                        "고칠 수 있는 범위가 정해져 있다면 그 파일만 직접 수정해라." % sub)
            elif exe == 'find' and any(a in ('-delete', '-exec', '-execdir', '-ok', '-okdir')
                                       for a in args):
                out("`find -exec/-delete` 는 무엇을 지울지 확인할 수 없어 허용되지 않는다.")
            elif exe in WRITERS:
                pos = [a for a in args if not a.startswith('-') and a.strip('"\'')]
                targets = write_targets(exe, args)
                for a in targets:
                    if SUB_TOKEN in a:
                        out("쓰기 대상이 명령 치환이라 어느 파일인지 알 수 없다.\n"
                            "경로를 그대로 적어라.")
                    if relative_and_unknown(a):
                        out("`cd -` / 서브셸 이동 뒤라 `%s` 가 어느 디렉토리인지 알 수 없다.\n"
                            "절대경로로 적거나, 이동을 한 번에 하나씩 해라." % a)
                    if path_forbidden(a):
                        out("`%s` 로 %s 를 고칠 수 없다." % (exe, a))
            track_cd(exe, args, struct)

    reset_cwd()
    if PUSH:
        # ── push 금지 (스코프 모드와 함께 걸릴 수 있으므로 독립적으로 본다) ──
        for seg in SEGMENTS:
            clean, redirs, struct = parse_redirects(seg)
            if not clean:
                continue
            exe, cmd, env = resolve_exe(clean)
            if exe_is_substitution(seg, struct):
                out("명령 이름 자리에 치환이 있어 무엇을 실행하는지 판정할 수 없다.\n"
                    "값을 먼저 구해서 명령을 그대로 적어라.")
            check_env(env, False)
            check_outside(clean, redirs, exe, cmd[1:])
            check_push_cmd(exe, cmd, struct)
            track_cd(exe, cmd[1:], struct)

    reset_cwd()
    if EDIT is None and not PUSH and WORKTREE:
        for seg in SEGMENTS:
            clean, redirs, struct = parse_redirects(seg)
            if not clean:
                continue
            exe, cmd, _ = resolve_exe(clean)
            check_outside(clean, redirs, exe, cmd[1:])
            track_cd(exe, cmd[1:], struct)


run_passes(SEGMENTS, TOKENS)
# 각 치환은 서브셸이라 원래 cwd 에서 돈다 — 별도로, 매번 cwd 를 초기화해 본다.
for _segs in SUB_SEGMENTS:
    run_passes(_segs, [t for seg in _segs for t in seg])

for pat in PATTERNS:
    try:
        if re.search(pat, CMD):
            out("차단된 명령이다: %s" % CMD[:80])
    except re.error:
        pass
