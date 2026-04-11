import { useState, useEffect } from 'react';
import { JsonTree } from '../shared/JsonTree';
import { useUiStore } from '../../store/uiStore';
import { t } from '../../../i18n';
import type { ProxyCapture } from '../../../domain/entities/ProxyCapture';

const PRICING_DATE = '2026-03-24';

interface Props {
  capture: ProxyCapture;
}

function calcPricing(model: string) {
  const isOpus4 = model.includes('opus-4-') && !model.includes('opus-4-1');
  const isOldOpus = model.includes('opus-4-1') || model.includes('opus-3');
  const isHaiku = model.includes('haiku');
  let inP = 3, outP = 15;
  if (isOpus4) { inP = 5; outP = 25; }
  else if (isOldOpus) { inP = 15; outP = 75; }
  else if (isHaiku) { inP = 1; outP = 5; }
  return { inP, outP, crP: inP * 0.1, cwP: inP };
}

function TokenPopover({ model, kb, totalIn, out, cacheRead, cacheWrite, uncached,
  costStr, cacheHit, inP, outP, crP, cwP, onClose }: any) {
  const fmtTok = (n: number) => n >= 1000 ? `${(n / 1000).toFixed(1)}K` : String(n);
  const fmtCost = (n: number) => `$${(n / 1_000_000).toFixed(4)}`;
  useEffect(() => {
    const h = (e: MouseEvent) => { if (!(e.target as Element).closest('.token-popover')) onClose(); };
    document.addEventListener('click', h, true);
    return () => document.removeEventListener('click', h, true);
  }, [onClose]);
  const rows = [
    { label: 'Cache Read', tokens: fmtTok(cacheRead), price: crP, cost: fmtCost(cacheRead * crP) },
    { label: 'Cache Write', tokens: fmtTok(cacheWrite), price: cwP, cost: fmtCost(cacheWrite * cwP) },
    { label: 'Uncached In', tokens: fmtTok(uncached), price: inP, cost: fmtCost(uncached * inP) },
    { label: 'Output', tokens: fmtTok(out), price: outP, cost: fmtCost(out * outP) },
  ];
  return (
    <div className="token-popover" onClick={e => e.stopPropagation()}>
      <div className="token-popover-title">
        <span>토큰 비용 분석</span>
        <span className="token-popover-copy" onClick={() => navigator.clipboard.writeText(`${model} ${kb}KB ${costStr}`)}>복사</span>
      </div>
      <div className="token-popover-info">{model || '(모델 미상)'} · {kb} KB</div>
      {rows.map(r => (
        <div key={r.label} className="token-popover-row">
          <span className="tp-label">{r.label}</span>
          <span className="tp-formula">{r.tokens} × ${r.price}/MTok</span>
          <span className="tp-result">{r.cost}</span>
        </div>
      ))}
      <div className="token-popover-row tp-total"><span className="tp-label">합계</span><span className="tp-result">{costStr}</span></div>
      <div className="token-popover-row tp-total"><span className="tp-label">캐시 적중률</span><span className="tp-result">{cacheHit}%</span></div>
      <div className="token-popover-note">구독 요금 기준 · 기준일: {PRICING_DATE}</div>
    </div>
  );
}

function TokenCostRow({ body, model }: { body: unknown; model?: string }) {
  const [open, setOpen] = useState(false);
  const usage = (body as any)?.usage;
  if (!usage) return null;
  const totalIn = usage.input_tokens ?? 0;
  const out = usage.output_tokens ?? 0;
  const cacheRead = usage.cache_read_input_tokens ?? 0;
  const cacheWrite = usage.cache_creation_input_tokens ?? 0;
  const uncached = Math.max(0, totalIn - cacheRead - cacheWrite);
  const cacheHit = totalIn > 0 ? Math.round(cacheRead / totalIn * 100) : 0;
  const kb = Math.round(JSON.stringify(body).length / 1024 * 10) / 10;
  const { inP, outP, crP, cwP } = calcPricing(model ?? '');
  const cost = (uncached * inP + cacheRead * crP + cacheWrite * cwP + out * outP) / 1_000_000;
  const costStr = cost >= 0.001 ? `$${cost.toFixed(4)}` : `$${cost.toFixed(6)}`;

  return (
    <div className="token-info-row" style={{ cursor: 'pointer', position: 'relative' }} onClick={() => setOpen(o => !o)}>
      <span className="tt-badge">{kb} KB</span>
      <span className="tt-badge blue">in {totalIn.toLocaleString()}</span>
      <span className="tt-badge">out {out.toLocaleString()}</span>
      {cacheRead > 0 && <span className="tt-badge green">cache {cacheHit}%</span>}
      <span className="tt-badge yellow">{costStr}</span>
      {open && <TokenPopover
        model={model ?? ''} kb={kb}
        totalIn={totalIn} out={out} cacheRead={cacheRead} cacheWrite={cacheWrite} uncached={uncached}
        costStr={costStr} cacheHit={cacheHit} inP={inP} outP={outP} crP={crP} cwP={cwP}
        onClose={() => setOpen(false)}
      />}
    </div>
  );
}

export function ResponseTab({ capture }: Props) {
  const locale = useUiStore((s) => s.locale);
  const search = useUiStore((s) => s.search);
  const mechFilter = useUiStore((s) => s.mechFilter);
  const navIdx = useUiStore((s) => s.searchNavIdx);
  const setNavTotal = useUiStore((s) => s.setSearchNavTotal);

  if (!capture.response) {
    return (
      <div className="proxy-empty">{t(locale, 'proxy.waitingResponse')}</div>
    );
  }

  const model = (capture.body as any)?.model ?? '';

  return (
    <div style={{ flex: 1, overflow: 'auto' }}>
      <div style={{ padding: '8px 12px', fontSize: 11, color: 'var(--dim)', borderBottom: '1px solid var(--border)' }}>
        <span>Status: </span>
        <span style={{ color: capture.response.status >= 400 ? 'var(--red)' : 'var(--green)', fontWeight: 700 }}>
          {capture.response.status}
        </span>
      </div>
      <TokenCostRow body={capture.response.body} model={model} />
      {capture.response.body != null ? (
        <JsonTree data={capture.response.body} search={search || undefined} mechKey={mechFilter} navIdx={navIdx} onMatchTotal={setNavTotal} />
      ) : (
        <div className="proxy-empty">{t(locale, 'proxy.noBody')}</div>
      )}
    </div>
  );
}
