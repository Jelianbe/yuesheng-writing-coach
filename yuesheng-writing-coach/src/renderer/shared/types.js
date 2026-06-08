// 共享类型定义（ESM 格式）
// 纯运行时函数与常量，不含 TypeScript 类型声明
// 运行时常量请见 ./constants.js

/** 创建成功响应 */
function apiSuccess(data) {
    return { success: true, data };
}
/** 创建错误响应 */
function apiError(error) {
    return { success: false, error };
}

/** Persona 预设映射 */
export const PERSONA_PRESETS = {
    doubao: {
        id: 'doubao',
        label: '温柔陪伴型',
        tone: 'encouraging',
        challengeSize: 'micro',
        knowledgeScope: 'base',
        responseStyle: '先肯定再引导，多用提问少用判断',
    },
    yuesheng: {
        id: 'yuesheng',
        label: '老编辑型',
        tone: 'direct',
        challengeSize: 'full',
        knowledgeScope: 'full',
        responseStyle: '直击要害，给直接反馈，不绕弯',
    },
    direct: {
        id: 'direct',
        label: '挑战型',
        tone: 'challenging',
        challengeSize: 'medium',
        knowledgeScope: 'core',
        responseStyle: '持续施压，不满足于表面的答案',
    },
};

export { apiSuccess, apiError };
