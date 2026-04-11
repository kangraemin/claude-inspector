import { useEffect, useRef } from 'react';

// ── module-level globals (same as index.html) ──
let _jtId = 0;
let _jtLine = 0;

function esc(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function buildJsonHtml(val: unknown, depth: number, trailing: string, totalBytes: number): string {
  if (val === null) return `<span class="jt-null">null</span>${trailing}`;
  if (typeof val === 'boolean') return `<span class="jt-bool">${val}</span>${trailing}`;
  if (typeof val === 'number') return `<span class="jt-num">${val}</span>${trailing}`;
  if (typeof val === 'string') {
    const COLLAPSE_LEN = 300;
    if (val.length > COLLAPSE_LEN) {
      const sid = `jts${++_jtId}`;
      const preview = esc(val.slice(0, 80)).replace(/\\n/g, ' ').replace(/\n/g, ' ') + '…';
      const expanded = esc(val).replace(/\\n/g, '\n');
      const lines = expanded.split('\n');
      const baseLn = _jtLine;
      let expandedRows = '';
      for (let li = 0; li < lines.length; li++) {
        const ln = li === 0 ? baseLn : ++_jtLine;
        const isLast = li === lines.length - 1;
        const openQuote = li === 0 ? '"' : '';
        const closeQuote = isLast ? '"' : '';
        expandedRows += `<div class="jt-exp-line" data-ln="${ln}">${openQuote}${lines[li]}${closeQuote}</div>`;
      }
      return (
        `<span class="jt-str-long">` +
        `<span class="jt-str-toggle" id="${sid}-btn" data-jtstr="${sid}">▶</span>` +
        `<span class="jt-str-preview" id="${sid}-s" data-jtstr="${sid}">"${preview}" <span style="color:var(--dim);font-size:10px">(${val.length} chars)</span></span>` +
        `<div class="jt-str-expanded" id="${sid}-b" style="display:none">` +
        `<span class="jt-str-toggle" data-jtstr="${sid}">▼</span>` +
        expandedRows +
        `</div>` +
        `</span>${trailing}`
      );
    }
    return `<span class="jt-str">"${esc(val)}"</span>${trailing}`;
  }

  const isArr = Array.isArray(val);
  const entries: [string | null, unknown][] = isArr
    ? (val as unknown[]).map((v) => [null, v])
    : Object.entries(val as Record<string, unknown>);
  const open = isArr ? '[' : '{';
  const close = isArr ? ']' : '}';
  if (entries.length === 0) return `<span>${open}${close}</span>${trailing}`;

  const id = `jt${++_jtId}`;
  const label = String(entries.length);
  const rows = entries
    .map(([k, v], i) => {
      const ln = ++_jtLine;
      const comma = i < entries.length - 1 ? `<span style="color:var(--dim)">,</span>` : '';
      const keyPart =
        k !== null
          ? `<span class="jt-key">"${esc(String(k))}"</span><span style="color:var(--dim)">: </span>`
          : '';
      return `<div class="jt-row" data-ln="${ln}" style="padding-left:16px">${keyPart}${buildJsonHtml(v, depth + 1, comma, totalBytes)}</div>`;
    })
    .join('');

  const jsonBytes = new TextEncoder().encode(JSON.stringify(val)).length;
  const tokens = Math.ceil(jsonBytes / 3.5);
  const tokStr =
    tokens >= 1_000_000
      ? (tokens / 1_000_000).toFixed(1) + 'M'
      : tokens >= 1000
        ? (tokens / 1000).toFixed(1) + 'K'
        : String(tokens);
  const pct = totalBytes > 0 ? (jsonBytes / totalBytes) * 100 : 0;
  const pctStr = pct >= 1 ? pct.toFixed(0) + '%' : pct >= 0.1 ? pct.toFixed(1) + '%' : '<0.1%';
  const tokTag = `<span class="jt-tok">~${tokStr} tok · ${pctStr}</span>`;

  const closeLn = ++_jtLine;
  const typeTag = isArr ? `[${label}]` : `{${label}}`;
  return (
    `<span>` +
    `<span class="jt-btn" id="${id}-btn" data-jt="${id}">▼</span>` +
    `<span style="color:var(--dim)">${open}</span>` +
    `<span class="jt-tag" id="${id}-s" data-jt="${id}" style="display:none">${typeTag} ${tokTag}${trailing}</span>` +
    `<span id="${id}-b">` +
    rows +
    `<div class="jt-row" data-ln="${closeLn}"><span style="color:var(--dim)">${close}</span>${trailing}</div>` +
    `</span>` +
    `</span>`
  );
}

function renderToHtml(data: unknown): string {
  let obj: unknown;
  try {
    obj = typeof data === 'string' ? JSON.parse(data) : data;
  } catch {
    return `<pre>${esc(typeof data === 'string' ? data : JSON.stringify(data, null, 2))}</pre>`;
  }
  const totalBytes = new TextEncoder().encode(JSON.stringify(obj)).length;
  _jtLine = 0;
  return buildJsonHtml(obj, 0, '', totalBytes) + `<div class="jt-line-info">${_jtLine} lines total</div>`;
}

function jtToggle(id: string) {
  const body = document.getElementById(`${id}-b`);
  const summary = document.getElementById(`${id}-s`);
  const btn = document.getElementById(`${id}-btn`);
  if (!body || !summary || !btn) return;
  const open = body.style.display !== 'none';
  body.style.display = open ? 'none' : '';
  summary.style.display = open ? '' : 'none';
  btn.textContent = open ? '▶' : '▼';
}

function jtStrToggle(id: string) {
  const body = document.getElementById(`${id}-b`);
  const summary = document.getElementById(`${id}-s`);
  const btn = document.getElementById(`${id}-btn`);
  if (!body || !summary) return;
  const open = body.style.display !== 'none';
  body.style.display = open ? 'none' : '';
  summary.style.display = open ? '' : 'none';
  if (btn) btn.style.display = open ? '' : 'none';
}

function clearHighlight(container: HTMLElement, cls: string) {
  container.querySelectorAll(`span.${cls}`).forEach(el => {
    el.replaceWith(document.createTextNode(el.textContent ?? ''));
  });
  container.normalize();
}

function applySearchHighlight(container: HTMLElement, query: string) {
  const walker = document.createTreeWalker(container, NodeFilter.SHOW_TEXT);
  const nodes: Text[] = [];
  let node: Node | null;
  while ((node = walker.nextNode())) nodes.push(node as Text);
  const re = new RegExp(query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi');
  for (const tn of nodes) {
    if (!re.test(tn.textContent ?? '')) { re.lastIndex = 0; continue; }
    re.lastIndex = 0;
    const frag = document.createDocumentFragment();
    let last = 0, m: RegExpExecArray | null;
    const text = tn.textContent ?? '';
    while ((m = re.exec(text)) !== null) {
      if (m.index > last) frag.appendChild(document.createTextNode(text.slice(last, m.index)));
      const span = document.createElement('span');
      span.className = 'search-hl';
      span.textContent = m[0];
      frag.appendChild(span);
      last = m.index + m[0].length;
    }
    if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
    tn.parentNode?.replaceChild(frag, tn);
  }
}

function applyMechHighlight(container: HTMLElement, mechKey: string) {
  const tagMap: Record<string, string> = {
    cm: 'system-reminder',
    sc: 'command-message',
  };
  const tag = tagMap[mechKey];
  if (!tag) return;
  applySearchHighlight(container, tag);
  container.querySelector('.search-hl')?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  container.querySelectorAll('.search-hl').forEach(el => {
    (el as HTMLElement).className = 'mech-hl-text';
  });
}

interface JsonTreeProps {
  data: unknown;
  className?: string;
  search?: string;
  mechKey?: string | null;
}

export function JsonTree({ data, className, search, mechKey }: JsonTreeProps) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!ref.current) return;
    _jtId = 0;
    const html = renderToHtml(data);
    ref.current.innerHTML = html;

    // Event delegation for toggle clicks
    const handler = (e: MouseEvent) => {
      const target = e.target as HTMLElement;
      const jtId = target.closest('[data-jt]')?.getAttribute('data-jt');
      const jtStr = target.closest('[data-jtstr]')?.getAttribute('data-jtstr');
      if (jtId) jtToggle(jtId);
      else if (jtStr) jtStrToggle(jtStr);
    };
    ref.current.addEventListener('click', handler);
    return () => ref.current?.removeEventListener('click', handler);
  }, [data]);

  useEffect(() => {
    if (!ref.current) return;
    clearHighlight(ref.current, 'search-hl');
    if (search?.trim()) applySearchHighlight(ref.current, search.trim());
  }, [search, data]);

  useEffect(() => {
    if (!ref.current) return;
    clearHighlight(ref.current, 'mech-hl-text');
    if (mechKey) applyMechHighlight(ref.current, mechKey);
  }, [mechKey, data]);

  return (
    <div
      ref={ref}
      className={`json-tree-view jt-lined ${className ?? ''}`}
    />
  );
}
