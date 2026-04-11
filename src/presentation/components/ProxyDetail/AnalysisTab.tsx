import { useMemo } from 'react';
import { ResponseParserService } from '../../../domain/services/ResponseParserService';
import { useUiStore } from '../../store/uiStore';
import { t } from '../../../i18n';
import type { ProxyCapture } from '../../../domain/entities/ProxyCapture';

const parser = new ResponseParserService();

interface Props {
  capture: ProxyCapture;
}

export function AnalysisTab({ capture }: Props) {
  const locale = useUiStore((s) => s.locale);
  const detection = useMemo(() => parser.detectMechanisms(capture.body), [capture.body]);

  const hasAny =
    detection.claudeMd !== null ||
    detection.outputStyle !== null ||
    detection.slashCommand !== null ||
    detection.skills.length > 0 ||
    detection.subAgents.length > 0;

  if (!hasAny) {
    return (
      <div className="proxy-empty">
        {t(locale, 'analysis.noMechanisms')}
      </div>
    );
  }

  return (
    <div className="analysis-view" style={{ flex: 1, overflow: 'auto' }}>
      {detection.claudeMd !== null && (
        <div className="analysis-section">
          <div className="analysis-section-title" style={{ color: 'var(--green)' }}>
            📋 {t(locale, 'analysis.claudeMdTitle')}
          </div>
          <div className="analysis-block highlight-green" style={{ maxHeight: 300, overflow: 'auto' }}>
            {detection.claudeMd}
          </div>
        </div>
      )}

      {detection.outputStyle !== null && (
        <div className="analysis-section">
          <div className="analysis-section-title" style={{ color: 'var(--blue)' }}>
            🎨 {t(locale, 'analysis.outputStyleTitle')}
          </div>
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
          <div className="analysis-block highlight-yellow" style={{ maxHeight: 120, overflow: 'auto' }}>
            {detection.slashCommand.tag}
          </div>
        </div>
      )}

      {detection.skills.length > 0 && (
        <div className="analysis-section">
          <div className="analysis-section-title" style={{ color: 'var(--purple)' }}>
            🛠 {t(locale, 'analysis.skillTitle')}
          </div>
          {detection.skills.map((sk) => (
            <div key={sk.id} className="analysis-block highlight-purple" style={{ fontSize: 11 }}>
              {sk.id}
            </div>
          ))}
        </div>
      )}

      {detection.subAgents.length > 0 && (
        <div className="analysis-section">
          <div className="analysis-section-title" style={{ color: 'var(--orange)' }}>
            🤖 {t(locale, 'analysis.subAgentTitle')}
          </div>
          {detection.subAgents.map((sa) => (
            <div key={sa.id} className="analysis-block highlight-orange" style={{ fontSize: 11 }}>
              {sa.name}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
