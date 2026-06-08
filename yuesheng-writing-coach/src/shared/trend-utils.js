/**
 * 趋势计算共享工具（ESM 格式）
 *
 * 消除 ability-profile.service.ts 和 student-model.service.ts
 * 两处 calcTrend 重复实现（CODE_SCAN Q5 / M1 / M3）
 */

/** 趋势改善阈值：当前平均 < 之前平均 × 此值 = 改善 */
export const TREND_IMPROVE_THRESHOLD = 0.8;
/** 趋势恶化阈值：当前平均 > 之前平均 × 此值 = 恶化 */
export const TREND_WORSEN_THRESHOLD = 1.2;

/**
 * 计算两个平均值之间的趋势方向
 */
function calcTrendFromAverages(currentAvg, previousAvg) {
    if (currentAvg < previousAvg * TREND_IMPROVE_THRESHOLD)
        return 'up';
    if (currentAvg > previousAvg * TREND_WORSEN_THRESHOLD)
        return 'down';
    return 'stable';
}

/**
 * 计算两组数据的趋势方向
 */
function calcTrend(recent, previous) {
    if (recent.length === 0 || previous.length === 0)
        return 'stable';
    const rAvg = recent.reduce((a, b) => a + b, 0) / recent.length;
    const pAvg = previous.reduce((a, b) => a + b, 0) / previous.length;
    return calcTrendFromAverages(rAvg, pAvg);
}

/**
 * 从完整历史计算趋势（自动从中间分割）
 */
function calcTrendFromHistory(history) {
    if (history.length < 2)
        return 'stable';
    const mid = Math.floor(history.length / 2);
    const firstHalf = history.slice(0, mid);
    const secondHalf = history.slice(mid);
    return calcTrend(secondHalf, firstHalf);
}

/**
 * 将原始趋势方向映射为教学友好的标签
 */
function mapTrendLabel(direction) {
    if (direction === 'up')
        return 'improving';
    if (direction === 'down')
        return 'worsening';
    return 'stable';
}

export { calcTrend, calcTrendFromAverages, calcTrendFromHistory, mapTrendLabel };
