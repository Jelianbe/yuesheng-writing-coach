import React from 'react';
import { GrowthChain } from '../shared/types';

interface Props {
  chains: GrowthChain[];
}

const STATUS_COLORS: Record<string, string> = {
  active: 'bg-red-500',
  improving: 'bg-amber-500',
  resolved: 'bg-emerald-500',
  recurred: 'bg-red-400',
};

const EVENT_ICONS: Record<string, string> = {
  diagnosis: '🔍',
  training: '📝',
  evaluation: '📊',
};

export function GrowthTimeline({ chains }: Props): React.ReactElement {
  if (chains.length === 0) {
    return (
      <div className="text-xs text-slate-500 text-center py-4">
        暂无成长记录，完成诊断和训练后自动生成
      </div>
    );
  }

  const sortedChains = [...chains].sort((a, b) => {
    const aLast = a.timeline[a.timeline.length - 1]?.date ?? '';
    const bLast = b.timeline[b.timeline.length - 1]?.date ?? '';
    return bLast.localeCompare(aLast);
  });

  return (
    <div className="flex flex-col gap-3">
      {sortedChains.map((chain) => {
        const statusColor = STATUS_COLORS[chain.status] ?? 'bg-slate-500';
        return (
          <div key={chain.chainId} className="bg-slate-800/50 rounded-lg p-3">
            <div className="flex items-center justify-between mb-2">
              <div className="flex items-center gap-2">
                <span className="text-xs font-bold text-slate-300">
                  {chain.abilityId}
                </span>
                <span className="text-xs text-slate-500">
                  {chain.syndromeId}
                </span>
              </div>
              <div className="flex items-center gap-1.5">
                <span className={`w-2 h-2 rounded-full ${statusColor}`} />
                <span className="text-xs text-slate-400">
                  {chain.scoreFrom} → {chain.scoreTo}
                </span>
              </div>
            </div>
            <div className="flex flex-col gap-1.5">
              {chain.timeline.slice(-3).map((event, i) => (
                <div key={i} className="flex items-center gap-2 text-xs">
                  <span>{EVENT_ICONS[event.eventType] ?? '·'}</span>
                  <span className="text-slate-400 min-w-[70px]">
                    {event.date?.slice(0, 10)}
                  </span>
                  <span className="text-slate-500">
                    {event.severity ? `L${event.severity.replace('L', '')}` : ''}
                  </span>
                  {event.score && (
                    <span className="text-slate-400">{event.score}分</span>
                  )}
                  {event.sampleText && (
                    <span className="text-slate-500 truncate max-w-[120px]">
                      "{event.sampleText.slice(0, 20)}..."
                    </span>
                  )}
                </div>
              ))}
            </div>
            {chain.improvement && (
              <div className="mt-1.5 text-xs text-emerald-400/80">
                {chain.improvement}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}
