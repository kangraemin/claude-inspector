import { useMemo, useEffect, useRef } from 'react';
import { ResponseParserService } from '../../../domain/services/ResponseParserService';
import { useUiStore } from '../../store/uiStore';
import { JsonTree } from '../shared/JsonTree';
import { t } from '../../../i18n';
import type { ProxyCapture } from '../../../domain/entities/ProxyCapture';

const parser = new ResponseParserService();

interface Props {
  capture: ProxyCapture;
}

export function AnalysisTab({ capture }: Props) {
  const locale = useUiStore((s) => s.locale);
  const search = useUiStore((s) => s.search);
  const detection = useMemo(() => parser.detectMechanisms(capture.body), [capture.body]);
  const viewRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!viewRef.current) return;
    viewRef.current.querySelectorAll('mark.search-hl').forEach(m => {
      const parent = m.parentNode;
      if (parent) { parent.replaceChild(document.createTextNode(m.textContent ?? ''), m); parent.normalize(); }
    });
    if (!search?.trim()) return;
    const walk = (node: Node) => {
      if (node.nodeType === 3) {
        const text = node.textContent ?? '';
        const idx = text.toLowerCase().indexOf(search.toLowerCase());
        if (idx >= 0) {
          const range = document.createRange();
          range.setStart(node, idx); range.setEnd(node, idx + search.length);
          const mark = document.createElement('mark');
          mark.className = 'search-hl';
          range.surroundContents(mark);
        }
      } else if (node.nodeType === 1 && !['SCRIPT','STYLE','MARK'].includes((node as Element).tagName)) {
        [...node.childNodes].forEach(walk);
      }
    };
    walk(viewRef.current);
  }, [search]);

  const hasAny =
    detection.claudeMd !== null ||
    detection.outputStyle !== null ||
    detection.slashCommand !== null ||
    detection.skills.length > 0 ||
    detection.subAgents.length > 0 ||
    detection.mcpTools.length > 0;

  if (!hasAny) {
    return (
      <div className="proxy-empty">
        {t(locale, 'analysis.noMechanisms')}
      </div>
    );
  }

  const slashSkillLinked = detection.slashCommand !== null && detection.skills.length > 0;

  return (
    <div ref={viewRef} className="analysis-view" style={{ flex: 1, overflow: 'auto' }}>
      {/* Model info */}
      {(capture.body as any)?.model && (
        <div className="analysis-kv" style={{ padding: '8px 12px', borderBottom: '1px solid var(--border)' }}>
          <span className="ak">model</span>
          <span className="av">{(capture.body as any).model}</span>
        </div>
      )}

      {detection.claudeMd !== null && (
        <div className="analysis-section">
          <div className="analysis-section-title" style={{ color: 'var(--green)' }}>
            📋 {t(locale, 'analysis.claudeMdTitle')}
          </div>
          <div className="analysis-desc">{t(locale, 'analysis.claudeMdDesc')}</div>
          {(() => {
            const sections = parser.parseClaudeMdSections(detection.claudeMd!);
            return sections.length > 0 ? sections.map((s, i) => (
              <div key={i} style={{ marginBottom: 6 }}>
                <div style={{ fontSize: 10, color: s.scope === 'global' ? 'var(--green)' : 'var(--blue)', marginBottom: 2, fontWeight: 600 }}>{s.label}</div>
                {s.path && <div style={{ fontSize: 10, color: 'var(--dim)', opacity: 0.6, marginBottom: 3, wordBreak: 'break-all' }}>{s.path}</div>}
                <div className={`analysis-block highlight-${s.cls}`} style={{ maxHeight: 200, overflow: 'auto' }}>{s.content}</div>
              </div>
            )) : (
              <div className="analysis-block highlight-green" style={{ maxHeight: 300, overflow: 'auto' }}>{detection.claudeMd}</div>
            );
          })()}
        </div>
      )}

      {detection.outputStyle !== null && (
        <div className="analysis-section">
          <div className="analysis-section-title" style={{ color: 'var(--blue)' }}>
            🎨 {t(locale, 'analysis.outputStyleTitle')}
          </div>
          <div className="analysis-desc">{t(locale, 'analysis.outputStyleDesc')}</div>
          {detection.outputStyle.map((s, i) => (
            <div key={i} className="analysis-block highlight-blue" style={{ fontSize: 11, maxHeight: 120, overflow: 'auto' }}>
              {s}
            </div>
          ))}
        </div>
      )}

      {detection.slashCommand !== null && (
        <div className="analysis-section">
          <div className="analysis-section-title" style={{ color: 'var(--yellow)' }}>
            ⌘ {t(locale, 'analysis.slashCmdTitle')}
          </div>
          <div className="analysis-desc">{t(locale, 'analysis.slashCmdDesc', { cmd: detection.slashCommand.tag.slice(0, 20) })}</div>
          <div className="analysis-block highlight-yellow" style={{ maxHeight: 120, overflow: 'auto' }}>
            {detection.slashCommand.tag}
          </div>
        </div>
      )}

      {detection.skills.length > 0 && (
        <div className="analysis-section">
          <div className="analysis-section-title" style={{ color: 'var(--purple)' }}>
            🛠 {t(locale, slashSkillLinked ? 'analysis.skillLinkedTitle' : 'analysis.skillTitle')}
          </div>
          <div className="analysis-desc">{t(locale, slashSkillLinked ? 'analysis.skillLinkedDesc' : 'analysis.skillDesc')}</div>
          {detection.skills.map((sk) => (
            <div key={sk.id} className="analysis-block highlight-purple" style={{ fontSize: 11 }}>
              <div className="analysis-kv"><span className="ak">id</span><span className="av">{sk.id}</span></div>
              <div style={{ maxHeight: 200, overflow: 'auto' }}>
                <JsonTree data={sk.input} />
              </div>
              {sk.result ? (
                <>
                  <div className="analysis-kv"><span className="ak">result (tool_result)</span></div>
                  <div className="analysis-block highlight-purple" style={{ fontSize: 11 }}>{sk.result}</div>
                </>
              ) : (
                <div className="analysis-kv"><span className="ak" style={{ color: 'var(--dim)' }}>{t(locale, 'analysis.noToolResult')}</span></div>
              )}
            </div>
          ))}
        </div>
      )}

      {detection.subAgents.length > 0 && (
        <div className="analysis-section">
          <div className="analysis-section-title" style={{ color: 'var(--orange)' }}>
            🤖 {t(locale, 'analysis.subAgentTitle')}
          </div>
          <div className="analysis-desc">{t(locale, 'analysis.subAgentDesc')}</div>
          {detection.subAgents.map((sa) => (
            <div key={sa.id} className="analysis-block highlight-orange" style={{ fontSize: 11 }}>
              <div className="analysis-kv">
                <span className="ak">subagent_type</span>
                <span className="av" style={{ color: 'var(--orange)' }}>{(sa.input as any)?.subagent_type || (sa.input as any)?.type || sa.name}</span>
              </div>
              <div style={{ maxHeight: 200, overflow: 'auto' }}>
                <JsonTree data={sa.input} />
              </div>
            </div>
          ))}
        </div>
      )}

      {detection.mcpTools.length > 0 && (
        <div className="analysis-section">
          <div className="analysis-section-title" style={{ color: '#4ec9dc' }}>🔌 MCP Tools</div>
          {detection.mcpTools.map((mc, i) => {
            const parts = mc.name.split('__');
            const serverName = parts[1] || '?';
            const toolName = parts.slice(2).join('__') || mc.name;
            return (
              <div key={mc.id || i} className="analysis-block" style={{ fontSize: 11, borderLeft: '2px solid rgba(78,201,220,.4)', background: 'rgba(78,201,220,.06)' }}>
                <div style={{ color: '#4ec9dc', fontWeight: 700, marginBottom: 4 }}>
                  {toolName} <span style={{ opacity: 0.6, fontWeight: 400 }}>({serverName})</span>
                </div>
                <div className="analysis-kv"><span className="ak">id</span><span className="av">{mc.id}</span></div>
                <div style={{ fontSize: 11 }}>
                  <JsonTree data={mc.input} />
                </div>
                {mc.result && (
                  <>
                    <div className="analysis-kv" style={{ marginTop: 6 }}><span className="ak">result (tool_result)</span></div>
                    <div className="analysis-block" style={{ borderLeft: '2px solid rgba(78,201,220,.4)', background: 'rgba(78,201,220,.06)', fontSize: 10 }}>{mc.result}</div>
                  </>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
