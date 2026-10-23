#!/usr/bin/env python3
# 셸 명령이 push 금지와 worktree 경계를 어기는지, Edit/Write 대상이 엔진 파일인지 판정한다.
#
# 감사에서 배운 것:
#  · 판정 단위는 반드시 **세그먼트**여야 한다. 줄 전체의 첫 토큰만 보면
#    `bouncer status && git push` 가 통째로 통과한다.
#  · 래퍼(`env`, `nohup`, `xargs`…)와 환경변수 접두는 실행 파일 이름을 바꾼다.
#  · 단계별 파일 수정 금지(edit_files)·명령 패턴 금지는 지웠다. plan 은 Claude Code plan 모드가,
#    검증 단계 쓰기는 증거 무효화(코드 지문)가 맡는다(2026-10-23).
#
# 이건 샌드박스가 아니라 가드레일이다. 진짜 보장은 blocking 게이트가 한다.
#
# 출력: 차단 사유 (없으면 허용)
import os
import re
import sys

# 두 가지로 쓰인다:
#   guard.py --check-path <project> <파일경로> [cwd] [worktree]   Edit/Write 판정
#   guard.py <push> <project> [worktree] [cwd]                    Bash 판정 (stdin=명령)
if len(sys.argv) > 1 and sys.argv[1] == '--check-path':
    CHECK_PATH = True
    PROJECT = sys.argv[2]
    TARGET = sys.argv[3]
    CWD = sys.argv[4] if len(sys.argv) > 4 else PROJECT
    WORKTREE = sys.argv[5] if len(sys.argv) > 5 else ''
    CMD, PUSH = '', False
else:
    CHECK_PATH = False
    CMD = sys.stdin.read()
    PUSH = sys.argv[1] == "true"
    PROJECT = sys.argv[2]
    WORKTREE = sys.argv[3] if len(sys.argv) > 3 else ''
    CWD = sys.argv[4] if len(sys.argv) > 4 else PROJECT
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
# timeout 은 값을 위치인자로 받는다 (`timeout 5 cmd`)
DURATION = re.compile(r'^[0-9]+(\.[0-9]+)?[smhd]?$')
# 셸 인터프리터. 인라인 코드 안의 `git push` 를 찾을 때 쓴다.
INTERPRETERS = {'sh', 'bash', 'zsh', 'ksh', 'dash', 'fish', 'csh', 'tcsh'}
# 뒤에 곧바로 명령이 오는 키워드. 건너뛰고 진짜 명령을 본다.
SKIP_KEYWORDS = {'if', 'then', 'elif', 'else', 'do', 'while', 'until', 'select',
                 'fi', 'done', 'esac', '!', 'time'}

GIT_PUSH_SUBS = {'push', 'send-pack', 'svn', 'p4', 'request-pull'}
# 아는 서브커맨드 전부. 여기 없는 것이 서브커맨드 자리에 오면 치환에 가려진 것이다.


# 개행도 구분자다. 빠져 있어서 `ls\nrm -rf .ai-bouncer` 가 한 세그먼트로 읽혀
# exe='ls' 하나만 판정됐다.
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
    안 그러면 worktree 안 엔진 파일이 "프로젝트 밖"으로 보여 보호가 빠진다.
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


FIRST_ARG_NOT_PATH = {'chmod', 'chown', 'chgrp'}
VALUE_FLAGS = {'truncate': {'-s', '--size'}, 'mkdir': {'-m', '--mode'},
               'split': {'-b', '-l', '-n', '-a', '--bytes', '--lines',
                         '--number', '--suffix-length'},
               'rsync': {'--exclude', '--include', '--exclude-from', '--include-from',
                         '-e', '--rsh', '--files-from', '--filter', '-f', '--chmod',
                         '--log-file', '--partial-dir', '--compare-dest', '--link-dest'},
               'install': {'-m', '-o', '-g', '--mode', '--owner', '--group'},
               # 두 번째 위치인자가 출력이다. 값을 받는 플래그를 건너뛰고 세야 한다
               # (안 그러면 `xxd -l 32 a.js` 의 a.js 가 출력으로 읽힌다)
               'xxd': {'-c', '-cols', '-g', '-groupsize', '-l', '-len', '-o', '-s', '-seek'},
               'uniq': {'-f', '-s', '-w', '--skip-fields', '--skip-chars', '--check-chars'}}


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


def git_sub(cmd):
    """git 의 전역 옵션을 건너뛰고 서브커맨드를 찾는다. 치환이면 None."""
    i = 1
    while i < len(cmd):
        t = cmd[i]
        if t in ('-C', '--git-dir', '--work-tree', '--namespace', '--exec-path', '-c', '--config-env'):
            i += 2
            continue
        if t.startswith('-'):
            i += 1
            continue
        # 서브커맨드 자리에 변수·치환이 오면 무엇인지 알 수 없다
        if '$' in t or '`' in t or SUB_TOKEN in t:
            return None
        return t
    return ''


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
    if parts and parts[-1] in ENGINE_PARENTS and not p.startswith(('/', '$')):
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


def reset_cwd():
    """판정 패스를 새로 시작할 때 cd 추적을 초기화한다.

    앞 치환의 `cd` 가 다음 치환의 첫 세그먼트로 새면 다른 디렉토리로 판정한다.
    """
    EFFECTIVE_CWD[0] = ''


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


def _under(a, root):
    return bool(root) and (a == root or a.startswith(root + '/'))


def push_target_outside(cmd, env):
    """이 `git push` 가 프로젝트와 무관한 레포를 향하는가.

    push 금지는 **이 작업의** 검증 전 push 를 막으려는 것이다. library 처럼
    다른 레포에 기록하고 push 하는 것까지 막아서 매번 차단됐다.
    대상을 확실히 알 때만 연다 — 조금이라도 애매하면 False.
    """
    if cwd_unknown() or any(n.startswith('GIT_') for n in env):
        return False
    base = cwd_now()
    i = 1
    while i < len(cmd):
        t = cmd[i]
        if t == '-C':
            if i + 1 >= len(cmd):
                return False
            d = cmd[i + 1]
            if '$' in d or '`' in d or SUB_TOKEN in d:
                return False
            d = os.path.expanduser(d.strip('"\''))
            base = os.path.normpath(d if os.path.isabs(d) else os.path.join(base, d))
            i += 2
            continue
        if t in ('--git-dir', '--work-tree', '--namespace') \
           or t.startswith(('--git-dir=', '--work-tree=', '--namespace=')):
            return False
        if not t.startswith('-'):
            break
        i += 1
    top = _real(base)
    while top and top != '/' and not os.path.exists(os.path.join(top, '.git')):
        top = os.path.dirname(top)
    if not top or top == '/':
        return False
    for root in (PROJECT, WORKTREE):
        r = _real(root) if root else ''
        if r and (_under(top, r) or _under(r, top)):
            return False
    return True


# 커밋은 막지 않는다. 체인 명령이 통째로 막혀 같은 명령을 push 만 빼고 다시 치는 일이 반복됐다(2026-10-22 감사 36건).
PUSH_MSG = ("push가 차단되었다. push 는 finalize 단계에서만 한다.\n"
            "같은 명령에서 `git push` 부분만 빼고 다시 실행해라(add·commit 은 지금 해도 된다).")


# 모델은 push 를 숨기려 하지 않는다. `bash -c`·`source`·`env -i`·`git -c` 를 통째로 막던 검사는
# 실사용 차단 47건이 전부 정상 명령이었다(숨긴 push 0건, 2026-10-22 감사). 실제로 잡히는 것은
# 검증 전에 `git push` 를 그냥 치는 경우(46건)라 그 형태만 본다.
def check_push_cmd(exe, cmd, struct=(), env=()):
    if exe == 'git-push':
        out(PUSH_MSG)
    # 인라인 코드 안에 그대로 적힌 `git push` (`bash -c 'make && git push'`).
    # `--no-push`, `[].push`, `/push/{print}` 같은 정상 인자를 잡지 않도록 `git push` 형태만 본다.
    if exe in INTERPRETERS | {'awk', 'gawk', 'python', 'python3', 'perl', 'ruby', 'node', 'eval'} \
       and any(re.search(r'\bgit\b[^\n;|&]*\bpush\b', a) for a in cmd[1:]):
        out(PUSH_MSG)
    if exe != 'git':
        return
    sub = git_sub(cmd)
    if sub in GIT_PUSH_SUBS:
        if sub == 'push' and any(a in ('-n', '--dry-run') for a in cmd):
            return                      # 아무것도 보내지 않는다
        if sub == 'push' and push_target_outside(cmd, env):
            return                      # 이 작업과 무관한 다른 레포
        out(PUSH_MSG)
    if sub == 'subtree' and 'push' in cmd:
        out(PUSH_MSG)


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
    sys.exit(0)

# 셸로 엔진 파일을 건드리는지 해석하던 검사는 지웠다. 7일 차단 76건 중 state/.active 를
# 실제로 겨눈 건 1건이고 나머지는 ls·sed·find 같은 읽기 오탐이었다(2026-10-23 감사).
# Edit/Write 로 직접 고치는 것만 위에서 막는다.
if not PUSH and not WORKTREE:
    sys.exit(0)

TOKENS = tokenize(CMD)
if TOKENS is None:
    # 해석 못 한 명령을 통째로 막으면 grep 패턴 속 백틱 같은 읽기까지 막힌다(4건).
    # 판정할 게 push 뿐이면 push 가 보일 때만 막는다.
    if PUSH and 'push' in CMD:
        out("따옴표가 닫히지 않아 명령을 판정할 수 없다.")
    if not WORKTREE:
        sys.exit(0)
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
        break
    _seen.add(_sub)
    del SUBS[:]
    _t = lex(_sub)
    if _t is None:
        continue
    SUB_SEGMENTS.append(split_segments(_t))
    _work.extend(SUBS)


def run_passes(SEGMENTS, TOKENS):
    """한 명령(또는 치환 하나)에 대해 push 금지와 worktree 밖 쓰기를 본다."""
    reset_cwd()
    SUBSHELL_SEEN[0] = any(k == 'st' and t in ('(', ')') for t, k in TOKENS)
    for seg in SEGMENTS:
        clean, redirs, struct = parse_redirects(seg)
        if not clean:
            continue
        exe, cmd, env = resolve_exe(clean)
        check_outside(clean, redirs, exe, cmd[1:])
        if PUSH:
            check_push_cmd(exe, cmd, struct, env)
        track_cd(exe, cmd[1:], struct)


run_passes(SEGMENTS, TOKENS)
# 각 치환은 서브셸이라 원래 cwd 에서 돈다 — 별도로, 매번 cwd 를 초기화해 본다.
for _segs in SUB_SEGMENTS:
    run_passes(_segs, [t for seg in _segs for t in seg])
