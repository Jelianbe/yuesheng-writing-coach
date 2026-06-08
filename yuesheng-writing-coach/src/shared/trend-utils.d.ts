/**
 * 趋势计算共享工具
 *
 * 消除 ability-profile.service.ts 和 student-model.service.ts
 * 两处 calcTrend 重复实现（CODE_SCAN Q5 / M1 / M3）
 */
/** 趋势改善阈值：当前平均 < 之前平均 × 此值 = 改善 */
export declare const TREND_IMPROVE_THRESHOLD = 0.8;
/** 趋势恶化阈值：当前平均 > 之前平均 × 此值 = 恶化 */
export declare const TREND_WORSEN_THRESHOLD = 1.2;
/** 趋势方向（原始标签） */
export type TrendDirection = 'up' | 'down' | 'stable';
/**
 * 计算两个平均值之间的趋势方向
 * @param currentAvg 当前（最近）平均值
 * @param previousAvg 之前（更早）平均值
 */
export declare function calcTrendFromAverages(currentAvg: number, previousAvg: number): TrendDirection;
/**
 * 计算两组数据的趋势方向
 * @param recent 最近数据数组
 * @param previous 之前数据数组
 */
export declare function calcTrend(recent: number[], previous: number[]): TrendDirection;
/**
 * 从完整历史计算趋势（自动从中间分割）
 * @param history 完整历史数据数组
 */
export declare function calcTrendFromHistory(history: number[]): TrendDirection;
/**
 * 将原始趋势方向映射为教学友好的标签
 */
export declare function mapTrendLabel(direction: TrendDirection): 'improving' | 'worsening' | 'stable';
