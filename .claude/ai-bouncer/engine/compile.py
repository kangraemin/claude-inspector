#!/usr/bin/env python3
"""workflow.yaml -> workflow.compiled.json

hook은 컴파일 결과(json)만 읽는다. yaml 파싱은 여기서 한 번만 일어난다.
pyyaml이 있으면 쓰고, 없으면 내장 파서로 폴백한다 (macOS 기본 python3엔 pyyaml이 없다).
"""
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone

# ─────────────────────────────────────────────────────────────
# YAML 로딩
# ─────────────────────────────────────────────────────────────


def _strip_comment(line):
    out, quote = [], None
    for i, ch in enumerate(line):
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            out.append(ch)
        elif ch == '#' and (i == 0 or line[i - 1] in ' \t'):
            break
        else:
            out.append(ch)
    return ''.join(out).rstrip()


def _split_flow(s):
    parts, buf, quote, depth = [], [], None, 0
    for ch in s:
        if quote:
            buf.append(ch)
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            buf.append(ch)
        elif ch in '[{':
            depth += 1
            buf.append(ch)
        elif ch in ']}':
            depth -= 1
            buf.append(ch)
        elif ch == ',' and depth == 0:
            parts.append(''.join(buf))
            buf = []
        else:
            buf.append(ch)
    if buf:
        parts.append(''.join(buf))
    return [p.strip() for p in parts if p.strip()]


def _scalar(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    if v.startswith('[') and v.endswith(']'):
        return [_scalar(x) for x in _split_flow(v[1:-1])]
    if v.startswith('{') and v.endswith('}'):          # 플로우 매핑
        out = {}
        for item in _split_flow(v[1:-1]):
            k, sep, val = item.partition(':')
            if sep:
                out[_scalar(k.strip())] = _scalar(val)
        return out
    low = v.lower()
    if low in ('true', 'yes'):
        return True
    if low in ('false', 'no'):
        return False
    if low in ('null', '~', ''):
        return None
    for cast in (int, float):
        try:
            return cast(v)
        except ValueError:
            pass
    return v


ANCHOR_RE = re.compile(r'(^|\s)[*&][A-Za-z_][\w-]*\s*$')


def mini_yaml(text):
    """필요한 YAML 부분집합만 지원하는 무의존 파서.

    지원: 중첩 매핑, 리스트, 플로우 리스트/매핑, 블록 스칼라(| |- > >-), 따옴표, 주석.
    미지원: 앵커/별칭(컴파일 시 거부), 다중 문서, 복합 키.
    """
    lines = text.replace('\t', '    ').split('\n')
    pos = [0]

    def peek():
        while pos[0] < len(lines):
            s = _strip_comment(lines[pos[0]])
            if s.strip() == '':
                pos[0] += 1
                continue
            return s, len(s) - len(s.lstrip(' '))
        return None, None

    def block_scalar(parent_indent, style):
        buf, base = [], None
        while pos[0] < len(lines):
            raw = lines[pos[0]]
            if raw.strip() == '':
                buf.append('')
                pos[0] += 1
                continue
            cur = len(raw) - len(raw.lstrip(' '))
            if cur <= parent_indent:
                break
            if base is None:
                base = cur
            buf.append(raw[base:] if len(raw) >= base else raw.strip())
            pos[0] += 1
        while buf and buf[-1] == '':
            buf.pop()
        body = (' '.join(l.strip() for l in buf if l.strip())
                if style.startswith('>') else '\n'.join(buf))
        return body if style.endswith('-') else body + '\n'

    def parse_any(indent):
        line, ind = peek()
        if line is None or ind < indent:
            return None
        return parse_list(ind) if line.lstrip().startswith('-') else parse_map(ind)

    def parse_list(indent):
        out = []
        while True:
            line, ind = peek()
            if line is None or ind != indent:
                break
            body = line.lstrip()
            if not (body == '-' or body.startswith('- ')):
                break
            rest = body[1:].strip()
            if rest == '':
                pos[0] += 1
                out.append(parse_any(indent + 1))
                continue
            key, sep, _ = rest.partition(':')
            if sep and not key.strip().startswith(('[', '{', '"', "'")):
                lines[pos[0]] = ' ' * (indent + 2) + rest
                out.append(parse_map(indent + 2))
            else:
                pos[0] += 1
                out.append(_scalar(rest))
        return out

    def parse_map(indent):
        out = {}
        while True:
            line, ind = peek()
            if line is None or ind != indent:
                break
            body = line.strip()
            if body.startswith('- '):
                break
            key, sep, val = body.partition(':')
            if not sep:
                break
            pos[0] += 1
            key = _scalar(key.strip())
            val = val.strip()
            if val in ('|', '|-', '>', '>-'):
                out[key] = block_scalar(ind, val)
            elif val == '':
                out[key] = parse_any(ind + 1)
            else:
                out[key] = _scalar(val)
        return out

    return parse_any(0) or {}


def load_yaml(path, force_mini=False):
    with open(path, encoding='utf-8') as fh:
        text = fh.read()
    if not force_mini:
        try:
            import yaml  # noqa
            return yaml.safe_load(text), 'pyyaml'
        except ImportError:
            pass
    # 내장 파서는 앵커를 조용히 먹어버린다 — 머신마다 뜻이 달라지므로 거부한다.
    for n, line in enumerate(text.split('\n'), 1):
        s = _strip_comment(line)
        if ANCHOR_RE.search(s):
            raise ConfigError(
                '%d행: 내장 YAML 파서는 앵커/별칭(&, *)을 지원하지 않는다. '
                '이 머신엔 pyyaml이 없어 조용히 무시되므로 거부한다 — 값을 직접 적어라.' % n)
    return mini_yaml(text), 'builtin'


# ─────────────────────────────────────────────────────────────
# 스키마
# ─────────────────────────────────────────────────────────────

STAGE_KEYS = {'steps', 'forbid', 'on_fail'}
STEP_KEYS = {'label', 'inject', 'inject_file', 'run', 'by', 'timeout', 'blocking', 'optional'}
ENGINE_TIMEOUT_MAX = 60   # Stop hook 예산을 먹지 않게. 넘으면 by: model을 써야 한다.
FORBID_KEYS = {'edit_files', 'push', 'bash', 'reason'}
BLOCKING_VALUES = (True, 'plan_approved')
SKILL_RE = re.compile(r'^skill:[A-Za-z0-9][\w.-]*$')


def _valid_blocking(v):
    return v in BLOCKING_VALUES or (isinstance(v, str) and SKILL_RE.match(v))


class ConfigError(Exception):
    pass


def _err(where, msg):
    raise ConfigError('%s: %s' % (where, msg))


def _compile_steps(stage, items, base_dir, sources):
    if items is None:
        return []
    if not isinstance(items, list):
        _err('stages.%s.steps' % stage, '리스트여야 한다')

    out, seen = [], set()
    for i, item in enumerate(items):
        where = 'stages.%s.steps[%d]' % (stage, i)
        if not isinstance(item, dict):
            _err(where, '매핑이어야 한다')
        unknown = set(item) - STEP_KEYS
        if unknown:
            _err(where, '알 수 없는 키: %s' % ', '.join(sorted(unknown)))

        kinds = [k for k in ('inject', 'inject_file', 'run') if k in item]
        if len(kinds) != 1:
            _err(where, 'inject / inject_file / run 중 정확히 하나여야 한다 (현재: %s)'
                 % (', '.join(kinds) or '없음'))
        kind = kinds[0]

        blocking = item.get('blocking')
        if blocking is not None and not _valid_blocking(blocking):
            _err(where, 'blocking 값은 true / plan_approved / skill:<이름> 만 가능하다 '
                        '(현재: %r)' % blocking)
        if blocking != True and blocking is not None and kind == 'run':
            _err(where, '%r는 inject 전용이다 — 도구 사용을 hook이 관찰하는 방식이라 '
                        '셸 명령에는 적용할 수 없다' % blocking)

        optional = item.get('optional', False)
        if not isinstance(optional, bool):
            _err(where, 'optional은 true/false여야 한다 — 질문 문구는 label에서 자동 생성된다')

        label = item.get('label')
        if optional and not label:
            _err(where, 'optional이면 label이 필수다 — 시작 시 선택지에 표시되는 이름이다')
        if blocking is not None and not label:
            _err(where, 'blocking이 있으면 label이 필수다 '
                        '(진행 상태를 위치가 아닌 이름으로 추적하므로, '
                        'yaml을 편집해도 진행 중 작업이 깨지지 않는다)')
        if label:
            if label in seen:
                _err(where, '같은 스테이지 안에 중복된 label: %r' % label)
            seen.add(label)

        step = {'id': '%s/%s' % (stage, label or i),
                'label': label or '',
                'blocking': blocking,
                'optional': optional}

        if kind == 'run':
            by = item.get('by', 'model')
            if by not in ('model', 'engine'):
                _err(where, "by는 model 또는 engine이어야 한다 (현재: %r)" % by)
            timeout = int(item.get('timeout', 30 if by == 'engine' else 600))
            if by == 'engine' and timeout > ENGINE_TIMEOUT_MAX:
                _err(where,
                     'by: engine의 timeout은 %d초를 넘을 수 없다 (현재 %d). '
                     '엔진은 Stop hook 안에서 실행하므로 오래 걸리면 hook이 타임아웃되고 '
                     '판정 없이 워크플로우가 멈춘다 — `by: model`을 써라.'
                     % (ENGINE_TIMEOUT_MAX, timeout))
            step['kind'] = 'run'
            step['run'] = item['run']
            step['by'] = by
            step['timeout'] = timeout
        else:
            step['kind'] = 'inject'
            if kind == 'inject':
                text = item['inject']
                if not isinstance(text, str) or not text.strip():
                    _err(where, 'inject는 비어 있지 않은 문자열이어야 한다')
            else:
                path = os.path.join(base_dir, item['inject_file'])
                if not os.path.isfile(path):
                    _err(where, '프롬프트 파일이 없다: %s' % path)
                with open(path, encoding='utf-8') as fh:
                    text = fh.read()
                sources.append(path)
                step['source'] = item['inject_file']
            step['text'] = text.rstrip()
            for k in ('timeout', 'by'):
                if k in item:
                    _err(where, '%s는 run 전용이다' % k)
        out.append(step)
    return out


def _compile_forbid(stage, forbid):
    empty = {'edit_files': None, 'push': False, 'bash': [], 'reason': ''}
    if forbid is None:
        return empty
    if not isinstance(forbid, dict):
        _err('stages.%s.forbid' % stage, '매핑이어야 한다')
    unknown = set(forbid) - FORBID_KEYS
    if unknown:
        _err('stages.%s.forbid' % stage, '알 수 없는 키: %s' % ', '.join(sorted(unknown)))

    edit = forbid.get('edit_files')
    if edit is not None and not isinstance(edit, (bool, list)):
        _err('stages.%s.forbid.edit_files' % stage, 'true 또는 glob 배열이어야 한다')

    patterns = forbid.get('bash') or []
    if not isinstance(patterns, list):
        _err('stages.%s.forbid.bash' % stage, '정규식 배열이어야 한다')
    for p in patterns:
        try:
            re.compile(p)
        except re.error as exc:
            _err('stages.%s.forbid.bash' % stage, '정규식 오류 `%s` — %s' % (p, exc))

    if (edit or forbid.get('push') or patterns) and not forbid.get('reason'):
        _err('stages.%s.forbid' % stage,
             'reason이 필요하다 — 차단당한 모델에게 이유를 알려주지 않으면 헤맨다')

    return {'edit_files': edit, 'push': bool(forbid.get('push', False)),
            'bash': list(patterns), 'reason': forbid.get('reason', '')}


ROOT_KEYS = {'version', 'settings', 'workflows', 'stages'}

# 기본값은 코드에 둔다. yaml은 덮어쓰기만 한다 —
# 그래야 새 설정이 생겨도 기존 yaml을 고칠 필요가 없다.
SETTINGS = {
    'update_branch': 'main',
    'update_check': True,
    'update_check_interval_hours': 6,
    'max_attempts': 3,
    'max_continue': 10,
    'stale_lock_hours': 12,
    'repo': 'kangraemin/ai-bouncer',
}


def compile_config(raw, base_dir, sources):
    if not isinstance(raw, dict):
        _err('root', '최상위는 매핑이어야 한다')
    unknown = set(raw) - ROOT_KEYS
    if unknown:
        _err('root', '알 수 없는 최상위 키: %s (가능: %s)'
             % (', '.join(sorted(unknown)), ', '.join(sorted(ROOT_KEYS))))
    if raw.get('version') != 1:
        _err('version', '지원하지 않는 버전 %r (1이어야 한다)' % raw.get('version'))

    settings = dict(SETTINGS)
    given = raw.get('settings') or {}
    if not isinstance(given, dict):
        _err('settings', '매핑이어야 한다')
    unknown = set(given) - set(SETTINGS)
    if unknown:
        _err('settings', '알 수 없는 설정: %s (가능: %s)'
             % (', '.join(sorted(unknown)), ', '.join(sorted(SETTINGS))))
    settings.update(given)

    stages_raw = raw.get('stages')
    if not isinstance(stages_raw, dict) or not stages_raw:
        _err('stages', '최소 1개 스테이지를 정의해야 한다')

    stages = {}
    for name, body in stages_raw.items():
        body = body or {}
        if not isinstance(body, dict):
            _err('stages.%s' % name, '매핑이어야 한다')
        unknown = set(body) - STAGE_KEYS
        if unknown:
            _err('stages.%s' % name, '알 수 없는 키: %s' % ', '.join(sorted(unknown)))
        stages[name] = {
            'name': name,
            'steps': _compile_steps(name, body.get('steps'), base_dir, sources),
            'forbid': _compile_forbid(name, body.get('forbid')),
            'on_fail': body.get('on_fail'),
        }

    workflows_raw = raw.get('workflows')
    if not isinstance(workflows_raw, dict) or not workflows_raw:
        _err('workflows', '최소 1개 워크플로우를 정의해야 한다')

    workflows = {}
    for wname, body in workflows_raw.items():
        body = body or {}
        unknown = set(body) - {'label', 'stages'}
        if unknown:
            _err('workflows.%s' % wname, '알 수 없는 키: %s' % ', '.join(sorted(unknown)))
        chain = body.get('stages')
        if not isinstance(chain, list) or not chain:
            _err('workflows.%s.stages' % wname, '비어 있지 않은 리스트여야 한다')
        if len(set(chain)) != len(chain):
            _err('workflows.%s.stages' % wname, '중복된 스테이지가 있다')
        for s in chain:
            if s not in stages:
                _err('workflows.%s.stages' % wname,
                     '정의되지 않은 스테이지 `%s` — 오타로 단계가 조용히 사라지는 것을 막는다' % s)
        if not body.get('label'):
            _err('workflows.%s' % wname, 'label이 필요하다 — 모드 선택지에 표시된다')
        workflows[wname] = {'label': body['label'], 'stages': chain}

    # on_fail은 같은 체인의 "앞선" 스테이지만 가리킬 수 있다 (무한 전진 방지)
    for wname, wf in workflows.items():
        chain = wf['stages']
        for idx, sname in enumerate(chain):
            target = stages[sname]['on_fail']
            if target in (None, 'abort'):
                continue
            if target not in chain:
                _err('stages.%s.on_fail' % sname,
                     '`%s`는 워크플로우 `%s`의 체인에 없다' % (target, wname))
            if chain.index(target) >= idx:
                _err('stages.%s.on_fail' % sname,
                     '`%s`는 앞선 스테이지가 아니다 — 되돌아가기만 허용된다' % target)

    used = {s for w in workflows.values() for s in w['stages']}
    orphans = sorted(set(stages) - used)
    if orphans:
        _err('stages', '어떤 워크플로우에도 쓰이지 않는 스테이지: %s' % ', '.join(orphans))

    return {'version': 1, 'settings': settings, 'workflows': workflows, 'stages': stages}


def main(argv):
    force_mini = '--builtin-parser' in argv
    argv = [a for a in argv if a != '--builtin-parser']
    if len(argv) < 2:
        sys.stderr.write('usage: compile.py <workflow.yaml> [out.json] [--builtin-parser]\n')
        return 2
    src, dst = argv[1], (argv[2] if len(argv) > 2 else None)
    if not os.path.isfile(src):
        sys.stderr.write('ai-bouncer: 워크플로우 파일 없음: %s\n' % src)
        return 2

    base_dir = os.path.dirname(os.path.abspath(src))
    sources = [os.path.abspath(src)]
    try:
        raw, parser = load_yaml(src, force_mini)
        compiled = compile_config(raw, base_dir, sources)
    except ConfigError as exc:
        sys.stderr.write('ai-bouncer: workflow.yaml 오류 — %s\n' % exc)
        return 1
    except Exception as exc:
        sys.stderr.write('ai-bouncer: workflow.yaml 파싱 실패 — %s\n' % exc)
        return 1

    # yaml + 참조된 프롬프트 파일 전체의 해시 — 하나라도 바뀌면 재컴파일된다
    digest = hashlib.sha256()
    for path in sources:
        with open(path, 'rb') as fh:
            digest.update(fh.read())
    compiled['source_sha256'] = digest.hexdigest()
    compiled['sources'] = [os.path.relpath(p, base_dir) for p in sources]
    compiled['compiled_at'] = datetime.now(timezone.utc).isoformat()
    compiled['parser'] = parser

    body = json.dumps(compiled, ensure_ascii=False, indent=2)
    if dst:
        tmp = dst + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as fh:
            fh.write(body + '\n')
        os.replace(tmp, dst)      # 원자적 교체 — 실패 시 기존 compiled.json 보존
    else:
        sys.stdout.write(body + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
