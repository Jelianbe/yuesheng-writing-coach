import React, { useState, useEffect } from 'react';
import { ChevronDown, ChevronUp, AlertCircle, FileText, Target, CheckSquare, BookOpen } from 'lucide-react';
import { Badge } from '../common/Badge';
import { BeatCheckChart } from './BeatCheckChart';
import type { DiagnosisEntry, EvidenceRecord, SeverityLevel } from '../../shared/types';
import { ActionNameMap } from '../../shared/display-names';
import { getVariantLabel } from '../../../shared/diagnosis-translations';
import { useDiagStore } from '../../stores/diag.store';
import { useChatStore } from '../../stores/chat.store';

interface DiagnosisCardProps {
  diagnosis: DiagnosisEntry;
  /** 点击"尝试修改"回调 */
  onStartEditing?: (syndromeId: string, evidence: string[], name: string, severity: string) => void;
}

const severityLabel: Record<SeverityLevel, string> = {
  L1: '轻度',
  L2: '中度',
  L3: '严重',
};

const severityBadge: Record<SeverityLevel, 'warning' | 'danger' | 'accent'> = {
  L1: 'warning',
  L2: 'warning',
  L3: 'danger',
};

/** 自检问题映射（引导用户自我发现，不替用户判断） */
const SELF_CHECK_QUESTIONS: Record<string, string[]> = {
  P001: ['你的开篇是否聚焦在一个具体场景上？', '读者能在前300字内看到一个清晰画面吗？', '这些世界观设定是"展示"出来的，还是"解释"出来的？'],
  P002: ['这个角色除了推动剧情，有自己的欲望和动机吗？', '如果把角色换成另一个人，故事走向会不同吗？'],
  P003: ['你是直接告诉读者"他很伤心"，还是通过动作/对话展现？', '这段情绪有具体的身体反应或行为表现吗？'],
  P004: ['这些背景信息是否真的需要现在告诉读者？', '能否通过角色的眼睛慢慢展现，而不是一次性倒出？'],
  P005: ['整段文字是否始终从同一个角色的视角出发？', '有没有突然跳到另一个角色"知道"或"感受"到的信息？'],
  P006: ['这段内容是在推进剧情/深化角色，还是在重复已知信息？', '读者读到这里会有"然后呢"的好奇，还是想跳过？'],
  P007: ['你的句式结构是否过于单一？', '长短句、叙述和描写的比例是否需要调整？'],
  P009: ['角色做这个决定的内在动机是什么？读者能理解为什么吗？', '如果删掉旁白解释，仅靠行动读者还能看懂动机吗？'],
  P010: ['你的原创角色是否有超越"设定"的真实人性反应？', '把角色放在日常场景中，他的反应还会像文中一样吗？'],
};

/**
 * DiagnosisCard — 诊断卡片
 *
 * 嵌入在 Chat 流中，默认折叠只显示摘要。
 * 展开后显示：证据片段、建议动作、自检清单。
 */
export const DiagnosisCard: React.FC<DiagnosisCardProps> = ({
  diagnosis,
  onStartEditing,
}) => {
  const [expanded, setExpanded] = useState(false);

  const topSyndrome = diagnosis.syndromes[0];

  if (!topSyndrome) return null;

  return (
    <div className="border border-border rounded-[var(--radius-md)] bg-surface shadow-sm overflow-hidden">
      {/* Summary row (always visible) */}
      <button
        onClick={() => setExpanded(!expanded)}
        className="w-full flex items-center gap-3 px-4 py-3 text-left hover:bg-surface-secondary transition-colors duration-fast"
        aria-expanded={expanded}
        aria-label="Toggle diagnosis details"
      >
        <div className="w-1 h-8 bg-accent-primary rounded-full flex-shrink-0" />
        <div className="flex-1 min-w-0">
          <p className="text-sm font-medium text-text-primary truncate">
            {topSyndrome.name}
          </p>
          <p className="text-xs text-text-tertiary mt-0.5">
            {topSyndrome.evidence[0]?.slice(0, 50)}...
          </p>
        </div>
        <div className="flex items-center gap-2 flex-shrink-0">
          {topSyndrome.variant && (
            <Badge variant="default">{getVariantLabel(topSyndrome.variant)}</Badge>
          )}
          <Badge variant={severityBadge[topSyndrome.severity]}>
            {severityLabel[topSyndrome.severity]}
          </Badge>
          {expanded ? (
            <ChevronUp className="w-4 h-4 text-text-tertiary" />
          ) : (
            <ChevronDown className="w-4 h-4 text-text-tertiary" />
          )}
        </div>
      </button>

      {/* Expanded details */}
      {expanded && (
        <div className="border-t border-border animate-expand">
          <div className="px-4 py-3 space-y-4">
            {/* SF-004: 叙事节拍完整性迷你图表 */}
            {diagnosis.beatCheck && (
              <BeatCheckChart beatCheck={diagnosis.beatCheck} />
            )}

            {diagnosis.syndromes.map((syndrome) => {
              const questions = SELF_CHECK_QUESTIONS[syndrome.id] ?? [];
              return (
                <div key={syndrome.id} className="space-y-2">
                  <div className="flex items-center gap-2">
                    <AlertCircle className="w-4 h-4 text-accent-primary" />
                    <span className="text-sm font-medium text-text-primary">
                      {syndrome.name}
                    </span>
                    {syndrome.variant && (
                      <Badge variant="default">{getVariantLabel(syndrome.variant)}</Badge>
                    )}
                    <Badge variant={severityBadge[syndrome.severity]}>
                      {severityLabel[syndrome.severity]}
                    </Badge>
                    {syndrome.score && (
                      <span className="text-xs text-text-tertiary ml-auto">
                        信号分: {syndrome.score.toFixed(1)}
                      </span>
                    )}
                  </div>

                  {/* 原文证据（从数据库获取） */}
                  <OriginalEvidenceSection syndromeId={syndrome.id} />

                  {/* Suggested actions */}
                  {syndrome.suggestedActions && syndrome.suggestedActions.length > 0 && (
                    <div>
                      <p className="text-xs font-medium text-text-secondary mb-1.5 flex items-center gap-1">
                        <Target className="w-3 h-3" />
                        建议动作
                      </p>
                      <div className="flex flex-wrap gap-1.5">
                        {syndrome.suggestedActions.map((actionId) => (
                          <Badge key={actionId} variant="accent">
                            {(ActionNameMap as Record<string, string>)[actionId] ?? actionId}
                          </Badge>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Self-check list: 替代治疗模式，引导用户自我发现 */}
                  {questions.length > 0 && (
                    <SelfCheckList questions={questions} />
                  )}

                  {/* Action buttons: 尝试修改 + 查看建议 */}
                  <div className="flex items-center gap-2 pt-1">
                    <button
                      type="button"
                      onClick={() => onStartEditing?.(syndrome.id, syndrome.evidence, syndrome.name, syndrome.severity)}
                      className="inline-flex items-center gap-1 px-2.5 py-1.5 text-xs font-medium rounded-[var(--radius-sm)]
                        bg-accent-primary/10 text-accent-primary hover:bg-accent-primary/20
                        transition-colors duration-fast"
                    >
                      ✏️ 尝试修改
                    </button>
                    {syndrome.suggestedActions && syndrome.suggestedActions.length > 0 && (
                      <button
                        type="button"
                        onClick={() => setExpanded(true)}
                        className="inline-flex items-center gap-1 px-2.5 py-1.5 text-xs font-medium rounded-[var(--radius-sm)]
                          bg-surface-secondary text-text-secondary hover:bg-border
                          transition-colors duration-fast"
                      >
                        📖 查看建议
                      </button>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
};

/** 自检清单子组件 */
const SelfCheckList: React.FC<{ questions: string[] }> = ({ questions }) => {
  const [checkedItems, setCheckedItems] = useState<Set<number>>(new Set());

  const allChecked = questions.length > 0 && questions.every((_, i) => checkedItems.has(i));

  const handleToggleCheck = (index: number) => {
    setCheckedItems(prev => {
      const next = new Set(prev);
      if (next.has(index)) next.delete(index);
      else next.add(index);
      return next;
    });
  };

  return (
    <div className="border border-border rounded-md overflow-hidden">
      <div className="px-3 py-2 bg-bg-tertiary/50 border-b border-border flex items-center gap-2">
        <CheckSquare className="w-3.5 h-3.5 text-accent-primary" />
        <span className="text-xs font-medium text-text-secondary">自检清单</span>
        {allChecked && (
          <span className="text-xs text-accent-success ml-auto">已自查 ✓</span>
        )}
      </div>
      <div className="px-3 py-2 space-y-1.5">
        {questions.map((q, i) => (
          <label
            key={i}
            className="flex items-start gap-2 py-1 cursor-pointer hover:text-text-primary transition-colors"
          >
            <input
              type="checkbox"
              checked={checkedItems.has(i)}
              onChange={() => handleToggleCheck(i)}
              className="mt-0.5 w-3.5 h-3.5 accent-accent-primary"
            />
            <span className={`text-xs ${checkedItems.has(i) ? 'text-text-muted line-through' : 'text-text-secondary'}`}>
              {q}
            </span>
          </label>
        ))}
      </div>
    </div>
  );
};

/**
 * 原文证据区块 — 从数据库获取证据并展示
 * 支持交叉引用标记（同段原文被多个症候引用时显示关联症候）
 */
const OriginalEvidenceSection: React.FC<{ syndromeId: string }> = ({ syndromeId }) => {
  const loadEvidence = useDiagStore((s) => s.loadEvidence);
  const getEvidence = useDiagStore((s) => s.getEvidence);
  const sessionId = useChatStore((s) => s.currentSessionId);
  const [evidence, setEvidence] = useState<EvidenceRecord[]>([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    // 先尝试从缓存获取
    const cached = getEvidence(syndromeId);
    if (cached.length > 0) {
      setEvidence(cached);
      return;
    }

    // 无缓存则从 IPC 加载
    if (!sessionId) return;
    setLoading(true);
    loadEvidence(syndromeId, sessionId)
      .then((records) => setEvidence(records))
      .finally(() => setLoading(false));
  }, [syndromeId, sessionId]);

  if (loading) {
    return (
      <div className="bg-highlight rounded-[var(--radius-sm)] p-3 border border-border-light">
        <p className="text-xs text-text-tertiary">加载原文证据...</p>
      </div>
    );
  }

  if (evidence.length === 0) return null;

  return (
    <div className="bg-highlight rounded-[var(--radius-sm)] border border-border-light overflow-hidden">
      <div className="px-3 py-2 bg-bg-tertiary/30 border-b border-border-light flex items-center gap-2">
        <BookOpen className="w-3.5 h-3.5 text-accent-primary" />
        <span className="text-xs font-medium text-text-secondary">原文证据</span>
      </div>
      <div className="p-3 space-y-2">
        {evidence.map((ev) => {
          // 解析 contentJson 获取原文片段和问题描述
          let text = '';
          let issue = '';
          let relatedDiseases: string[] = [];
          try {
            const content = typeof ev.contentJson === 'string'
              ? JSON.parse(ev.contentJson)
              : ev.contentJson;
            text = content.text ?? content.keyPassage ?? content.quote ?? '';
            issue = content.issue ?? content.description ?? content.problem ?? '';
            relatedDiseases = content.relatedDiseases ?? [];
          } catch {
            text = String(ev.contentJson).slice(0, 200);
          }

          return (
            <div key={ev.evidenceId} className="space-y-1">
              {text && (
                <div className="flex items-start gap-2">
                  <FileText className="w-3.5 h-3.5 text-text-tertiary mt-0.5 flex-shrink-0" />
                  <p className="text-sm text-text-secondary leading-relaxed italic">
                    "{text}"
                  </p>
                </div>
              )}
              {issue && (
                <p className="text-xs text-accent-warning pl-5">
                  ⚠️ {issue}
                </p>
              )}
              {/* 交叉引用标记：同段原文被多个症候引用 */}
              {relatedDiseases.length > 1 && (
                <p className="text-xs text-text-tertiary pl-5">
                  关联症候：{relatedDiseases.join(' · ')}
                </p>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
};
