/**
 * 消息路由服务
 *
 * V3：内容分类已由 DiagnosisAgent 自身完成（通过 contentType 字段），
 * 不再需要基于关键词的路由判断。
 * MessageRouter 保留为兼容层，shouldRunDiagnosis 始终返回 true，
 * 由 chat.handler 根据 DiagnosisAgent 返回的 contentType 决定是否生成诊断。
 */

/** 消息路由服务 */
export class MessageRouter {
  /**
   * 判断是否应该执行诊断流程
   * V3：始终返回 true，内容分类由 DiagnosisAgent 自身完成
   */
  shouldRunDiagnosis(_message: string): boolean {
    return true;
  }
}
