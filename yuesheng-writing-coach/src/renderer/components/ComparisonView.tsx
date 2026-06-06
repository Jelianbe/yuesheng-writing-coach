import React from 'react';
import { GrowthChain } from '../shared/types';
import { SYNDROME_NAMES } from '../../shared/mappings';

interface Props {
  chains: GrowthChain[];
}

export function ComparisonView({ chains }: Props): React.ReactElement {
  const resolvedOrImproved = chains.filter(
    c => c.status === 'resolved' || c.status === 'improving'
  );

  if (resolvedOrImproved.length === 0) {
    return (
      <div className="text-xs text-slate-500 text-center py-4">
        暂无对比数据。完成训练并改善症候后，这里会展示你的进步轨迹。
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      {resolvedOrImproved.map((chain) => {
        const firstDiag = chain.timeline.find(e => e.eventType === 'diagnosis');
        const lastEvent = chain.timeline[chain.timeline.length - 1];
        const scoreDiff = chain.scoreTo - chain.scoreFrom;
        const diffColor = scoreDiff > 0 ? 'text-emerald-400' : 'text-red-400';
        const diffLabel = scoreDiff > 0 ? `+${scoreDiff}` : `${scoreDiff}`;

        return (
          <div key={chain.chainId} className="bg-slate-800/50 rounded-lg p-3">
            <div className="flex items-center justify-between mb-2">
              <div className="flex items-center gap-2">
                <span className="text-xs text-slate-500">{chain.abilityId}</span>
                <span className="text-xs font-medium text-slate-300">
                  {SYNDROME_NAMES[chain.syndromeId] ?? chain.syndromeId}
                </span>
              </div>
              <span className={`text-xs font-bold ${diffColor}`}>{diffLabel}</span>
            </div>

            <div className="flex items-center gap-3 mb-2">
              <div className="flex-1">
                <div className="flex justify-between text-xs text-slate-500 mb-1">
                  <span>之前</span>
                  <span>{firstDiag?.date?.slice(0, 10) ?? '-'}</span>
                </div>
                <div className="h-2 bg-slate-700 rounded-full overflow-hidden">
                  <div
                    className="h-full bg-red-500/70 rounded-full"
                    style={{ width: `${chain.scoreFrom}%` }}
                  />
                </div>
                <div className="text-xs text-slate-400 mt-0.5">{chain.scoreFrom}分</div>
              </div>
              <div className="text-slate-600 text-lg">→</div>
              <div className="flex-1">
                <div className="flex justify-between text-xs text-slate-500 mb-1">
                  <span>现在</span>
                  <span>{lastEvent?.date?.slice(0, 10) ?? '-'}</span>
                </div>
                <div className="h-2 bg-slate-700 rounded-full overflow-hidden">
                  <div
                    className="h-full bg-emerald-500/70 rounded-full"
                    style={{ width: `${chain.scoreTo}%` }}
                  />
                </div>
                <div className="text-xs text-slate-400 mt-0.5">{chain.scoreTo}分</div>
              </div>
            </div>

            {chain.improvement && (
              <div className="text-xs text-slate-400 mt-1 pt-1.5 border-t border-slate-700/50">
                {chain.improvement}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}
