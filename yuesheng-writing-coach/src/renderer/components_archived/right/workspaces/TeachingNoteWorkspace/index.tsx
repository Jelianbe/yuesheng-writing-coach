import React, { useEffect, useState } from 'react';
import { Tree } from 'react-arborist';
import type { NodeRendererProps } from 'react-arborist';
import { getInvoke } from '../../../../utils/ipc';
import { IPC_CHANNELS } from '../../../../shared/constants';
import { registerWorkspace } from '../../../../registry/workspace-registry';
import type { ActiveProblem } from '../../../../../shared/types/types-teaching';
import styles from './index.module.css';

// ——— IPC 返回类型 ———
interface TreeNode {
  id: string;
  parentId: string | null;
  label: string;
  content: string;
  createdAt: number;
  children: TreeNode[];
}

interface TrainingRecord {
  recordId: string;
  syndromeId: string;
  title: string;
  score?: number;
  completedAt?: number;
}

// ——— Helpers ———
function relTime(ts: number): string {
  const d = Date.now() - ts;
  if (d < 864e5) return '今天';
  if (d < 1728e5) return '昨天';
  return Math.floor(d / 864e5) + '天前';
}

function severityColor(severity: string): string {
  if (severity === 'L3' || severity === 'high') return 'var(--error)';
  if (severity === 'L2' || severity === 'medium') return 'var(--warning)';
  return 'var(--text-tertiary)';
}

function severityLabel(s: string): string {
  if (s === 'L3' || s === 'high') return '严重';
  if (s === 'L2' || s === 'medium') return '中等';
  return '轻微';
}

// ——— react-arborist Node Renderer ———
const ArborNodeRenderer: React.FC<NodeRendererProps<TreeNode>> = ({ node, style, dragHandle }) => {
  const hasChildren = node.children && node.children.length > 0;
  return (
    <div style={style} className={styles.arborNode} ref={dragHandle}>
      <span
        className={styles.arborArrow}
        onClick={(e) => { e.stopPropagation(); node.toggle(); }}
      >
        {hasChildren ? (node.isOpen ? '▾' : '▸') : '·'}
      </span>
      <span className={styles.arborIcon}>{hasChildren ? '📁' : '📄'}</span>
      <span className={styles.arborLabel}>{node.data.label}</span>
    </div>
  );
};

// ——— Component ———
export const TeachingNoteWorkspace: React.FC = () => {
  const [treeNodes, setTreeNodes] = useState<TreeNode[] | null>(null);
  const [treeLoadError, setTreeLoadError] = useState<string | null>(null);
  const [selectedNote, setSelectedNote] = useState<{ label: string; content: string } | null>(null);
  const [recordLabel, setRecordLabel] = useState('');
  const [recordContent, setRecordContent] = useState('');
  const [recording, setRecording] = useState(false);

  // 从 IPC 加载的数据
  const [trainRecords, setTrainRecords] = useState<TrainingRecord[]>([]);
  const [activeProblems, setActiveProblems] = useState<ActiveProblem[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);

  // 加载教学笔记树 + 训练记录 + 诊断数据
  useEffect(() => {
    (async () => {
      try {
        // 1. 加载教学笔记树
        const treeData = await getInvoke()(IPC_CHANNELS.TEACHING_NOTE_GET_TREE, {});
        if (treeData && typeof treeData === 'object' && 'nodes' in treeData) {
          setTreeNodes((treeData as { nodes: TreeNode[] }).nodes);
        }

        // 2. 加载会话列表，再加载训练历史
        const sessionsData = await getInvoke()(IPC_CHANNELS.SESSION_LIST, {}) as {
          success: boolean; data?: { sessions: Array<{ id: string; title: string }> }; error?: string;
        };
        if (sessionsData?.success && sessionsData.data?.sessions) {
          const allTrainRecords: TrainingRecord[] = [];
          // 对每个会话检查是否有训练记录
          for (const session of sessionsData.data.sessions) {
            try {
              const histData = await getInvoke()(IPC_CHANNELS.TRAINING_HISTORY, { sessionId: session.id }) as {
                success: boolean; data?: { records: TrainingRecord[] }; error?: string;
              };
              if (histData?.success && histData.data?.records) {
                allTrainRecords.push(...histData.data.records.map(r => ({ ...r, title: r.title || session.title })));
              }
            } catch {
              // 单个会话查询失败不阻塞
            }
          }
          // 按 completedAt 倒序排列，没有日期的排末尾
          allTrainRecords.sort((a, b) => (b.completedAt ?? 0) - (a.completedAt ?? 0));
          setTrainRecords(allTrainRecords);
        }

        // 3. 加载诊断数据（取第一个有诊断结果的会话）
        if (sessionsData?.success && sessionsData.data?.sessions) {
          for (const session of sessionsData.data.sessions) {
            try {
              const diagData = await getInvoke()(IPC_CHANNELS.DIAGNOSIS_QUERY, { sessionId: session.id }) as {
                success: boolean; data?: ActiveProblem[]; error?: string;
              };
              if (diagData?.success && diagData.data && diagData.data.length > 0) {
                setActiveProblems(diagData.data);
                break; // 只取第一个有诊断结果的会话
              }
            } catch {
              // 跳过
            }
          }
        }
      } catch {
        setLoadError('部分数据加载失败');
        setTreeLoadError('无法加载教学笔记');
      }
    })();
  }, []);

  // 树节点拖拽移动
  const handleTreeMove = async (args: { dragIds: string[]; parentId: string | null; index: number }) => {
    if (args.dragIds.length === 0) return;
    try {
      await getInvoke()(IPC_CHANNELS.TEACHING_NOTE_UPDATE, {
        id: args.dragIds[0],
        parentId: args.parentId,
      });
    } catch {
      // 拖拽失败不阻塞
    }
  };

  // 记录新笔记
  const handleRecord = async () => {
    if (!recordLabel.trim()) return;
    setRecording(true);
    try {
      const result = await getInvoke()(IPC_CHANNELS.TEACHING_NOTE_RECORD, {
        sessionId: '',
        label: recordLabel.trim(),
        content: recordContent.trim() || recordLabel.trim(),
      });
      if (result) {
        const data = await getInvoke()(IPC_CHANNELS.TEACHING_NOTE_GET_TREE, {});
        if (data && typeof data === 'object' && 'nodes' in data) {
          setTreeNodes((data as { nodes: TreeNode[] }).nodes);
        }
        setRecordLabel('');
        setRecordContent('');
      }
    } catch {
      setTreeLoadError('记录失败');
    }
    setRecording(false);
  };

  const diagnosisSummary = activeProblems.length > 0
    ? `当前发现 ${activeProblems.length} 个问题症候：${activeProblems.map(p => p.name).join('、')}`
    : null;

  return (
    <div className={styles.wrap}>
      <h3 className={styles.title}>教学笔记</h3>

      {/* 最新诊断卡片 */}
      {activeProblems.length > 0 ? (
        <div className={styles.diagCard}>
          <div className={styles.diagSubtitle}>最新诊断</div>
          <div className={styles.diagSummary}>{diagnosisSummary}</div>
          {activeProblems.map(p => (
            <div key={p.id} className={styles.syndromeRow}>
              <span className={styles.dot} style={{ background: severityColor(p.severity) }} />
              <span className={styles.syndromeDesc}>{p.name}{p.evidence?.length ? `（${p.evidence.join('；')}）` : ''}</span>
              <span className={styles.severityLabel}>{severityLabel(p.severity)}</span>
            </div>
          ))}
        </div>
      ) : !loadError && (
        <div className={styles.diagCard}>
          <div className={styles.diagSubtitle}>诊断状态</div>
          <div className={styles.diagSummary}>暂无诊断数据。发送作品进行诊断后，结果将显示在这里。</div>
        </div>
      )}

      {/* 教练建议 */}
      {activeProblems.length > 0 && (
        <div className={styles.adviceSection}>
          <span className={styles.adviceLabel}>教练建议</span>
          <div className={styles.adviceText}>
            建议优先从 <span className={styles.adviceHighlight}>{activeProblems[0]?.name}</span> 入手训练。
            已推荐相关技法，可以从技法目录中选择开始。
          </div>
        </div>
      )}

      {/* 训练记录 */}
      <div className={styles.recordHeader}>
        <span className={styles.recordLabel}>
          训练记录 <span className={styles.recordCount}>({trainRecords.length} 条)</span>
        </span>
      </div>
      {trainRecords.length > 0 ? trainRecords.map(r => (
        <div key={r.recordId} className={styles.recordItem}>
          <div className={styles.recordRow}>
            <span className={styles.recordIcon}>◎</span>
            <span className={styles.recordName}>{r.title}</span>
          </div>
          <div className={styles.recordMeta}>
            {r.completedAt ? `${relTime(r.completedAt)}` : '进行中'}
            {r.score !== undefined ? ` | 得分 ${r.score}` : ''}
          </div>
        </div>
      )) : (
        <p className={styles.emptyText}>
          {loadError ? '加载失败' : '还没有训练记录。从技法目录开始第一个训练吧。'}
        </p>
      )}

      {/* [记录到教学笔记] 输入 */}
      <div className={styles.recordForm}>
        <input
          className={styles.recordInput}
          placeholder="笔记标题..."
          value={recordLabel}
          onChange={e => setRecordLabel(e.target.value)}
          onKeyDown={e => { if (e.key === 'Enter') handleRecord(); }}
        />
        <button
          className={recordLabel.trim() && !recording ? styles.recordBtn : styles.recordBtnDisabled}
          disabled={!recordLabel.trim() || recording}
          onClick={handleRecord}
        >
          {recording ? '...' : '记录'}
        </button>
      </div>

      {/* 教学笔记树 */}
      {treeNodes && treeNodes.length > 0 && (
        <div className={styles.treeSection}>
          <div className={styles.treeHeader}>
            <span className={styles.treeLabel}>教学笔记树</span>
            <span className={styles.treeBadge}>{treeNodes.length} 条</span>
          </div>
          <div className={styles.treeCard}>
            <Tree
              data={treeNodes}
              rowHeight={28}
              indent={16}
              openByDefault={false}
              width="auto"
              height={Math.min(treeNodes.length * 28 + 50, 300)}
              onActivate={(node) => {
                if (node.data.content) {
                  setSelectedNote({ label: node.data.label, content: node.data.content });
                }
              }}
              onMove={handleTreeMove}
            >
              {ArborNodeRenderer as React.FC<NodeRendererProps<TreeNode>>}
            </Tree>
          </div>
          {selectedNote && (
            <div className={styles.nodeDetail}>
              <div className={styles.nodeDetailTitle}>{selectedNote.label}</div>
              <div className={styles.nodeDetailContent}>{selectedNote.content}</div>
            </div>
          )}
          <div className={styles.treeFooter}>点击节点标题查看内容，拖拽节点可重新排序。</div>
        </div>
      )}

      {/* 加载中/错误提示 */}
      {!treeNodes && !treeLoadError && (
        <div className={styles.loadingText}>教学笔记树加载中（首次使用将自动创建）...</div>
      )}
      {treeLoadError && (
        <div className={styles.loadingText} style={{ color: 'var(--error)' }}>{treeLoadError}</div>
      )}
    </div>
  );
};

// ADR-002: 自注册
registerWorkspace({
  id: 'training',
  name: '教学笔记',
  icon: '✤',
  defaultOpen: true,
  component: () => import('./index').then(m => ({ default: m.TeachingNoteWorkspace })),
});
