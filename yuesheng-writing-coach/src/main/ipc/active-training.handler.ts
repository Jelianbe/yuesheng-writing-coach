/**
 * ActiveTraining IPC 处理器 — Sprint 24 A-3
 *
 * 职责: 接收渲染进程的训练草稿持久化请求,调用 ActiveTrainingService
 *
 * 通道:
 *   - activeTraining:updateDraft : 草稿保存 (renderer 500ms 防抖后调用)
 *   - activeTraining:get        : 查询当前 in_progress 训练 (供冷启动恢复)
 *
 * 设计:
 *   - 依赖通过 initActiveTrainingHandlers() 注入,模块级无变量
 *   - 业务逻辑全部委托给 ActiveTrainingService
 *   - 异常隔离: handler 内 try-catch 兜底,失败不污染主流程
 *
 * Sprint 24 A-4 增强:
 *   - 提供 setupActiveTrainingPush(mainWindow) 桥接函数
 *   - 订阅 ActiveTrainingService 状态变更,推送到 renderer
 *   - 通道: activeTraining:updated
 *
 * 依据: dev-docs/tasks/sprint-24-plan.md §A-3, §A-4
 */

import { BrowserWindow } from 'electron';
import { IPC_CHANNELS } from '../../shared/constants';
import { createHandler } from './utils/create-handler';
import { validatePayload } from './utils/validate-payload';
import type { ActiveTrainingService } from '../domains/03-teaching/state/active-training.service';
import type {
  ActiveTrainingUpdateDraftResponse,
  ActiveTrainingGetResponse,
  ActiveTrainingUpdatedEvent,
  ActiveTrainingStateChangeType,
} from '../../shared/api-contracts/active-training.contract';
import type { ActiveTraining } from '../domains/03-teaching/state/active-training.types';

/** DI 注入依赖 */
let activeTrainingService: ActiveTrainingService | null = null;

/**
 * 初始化 ActiveTraining handler 依赖
 * 必须在 registerActiveTrainingHandlers() 之前调用
 */
export function initActiveTrainingHandlers(service: ActiveTrainingService): void {
  activeTrainingService = service;
}

/**
 * 获取服务实例(内部使用,未初始化时抛错)
 */
function getService(): ActiveTrainingService {
  if (!activeTrainingService) {
    throw new Error(
      '[ActiveTrainingIPC] ActiveTrainingService not initialized. Call initActiveTrainingHandlers() first.',
    );
  }
  return activeTrainingService;
}

/**
 * 注册 ActiveTraining IPC 处理器
 * 应在主进程初始化阶段(ipc-registry.registerAll)调用
 */
export function registerActiveTrainingHandlers(): void {
  /**
   * activeTraining:updateDraft — 草稿保存
   * 业务逻辑: 调用 ActiveTrainingService.updateDraft()
   *   - 训练已 completed/aborted 时静默返回(草稿可丢弃)
   *   - 训练 in_progress 时持久化到 SQLite
   */
  createHandler<
    { sessionId: string; content: string },
    ActiveTrainingUpdateDraftResponse
  >(IPC_CHANNELS.ACTIVE_TRAINING_UPDATE_DRAFT, (_event, args) => {
    const validation = validatePayload<{ sessionId: string; content: string }>(args, {
      required: ['sessionId', 'content'],
      types: { sessionId: 'string', content: 'string' },
    });
    if (!validation.valid) {
      throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    }

    const { sessionId, content } = validation.data;
    const service = getService();
    const updated = service.updateDraft(sessionId, content);

    if (!updated) {
      // 训练可能已完成 / aborted / 不存在 — 草稿可丢弃
      return {
        success: false,
        length: content.length,
        persistedAt: new Date().toISOString(),
        status: service.getStatus(sessionId),
      };
    }

    return {
      success: true,
      length: content.length,
      persistedAt: updated.updatedAt,
      status: updated.status,
    };
  });

  /**
   * activeTraining:get — 查询当前 in_progress 训练
   * 用途: 冷启动恢复当前 session 的训练状态
   * 返回: null(无进行中训练) 或 ActiveTraining 完整快照
   */
  createHandler<{ sessionId: string }, ActiveTrainingGetResponse | null>(
    IPC_CHANNELS.ACTIVE_TRAINING_GET,
    (_event, args) => {
      const validation = validatePayload<{ sessionId: string }>(args, {
        required: ['sessionId'],
        types: { sessionId: 'string' },
      });
      if (!validation.valid) {
        throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
      }

      const service = getService();
      const active = service.getActive(validation.data.sessionId);
      if (!active) {
        return null;
      }

      // 领域对象 → IPC 响应(字段映射)
      const response: ActiveTrainingGetResponse = {
        sessionId: active.sessionId,
        challengeId: active.challengeId,
        challengeName: active.challengeName,
        mode: active.mode,
        currentStepIndex: active.currentStepIndex,
        steps: active.steps,
        userDraft: active.userDraft,
        flowType: active.flowType,
        trainingFlow: active.trainingFlow,
        recordId: active.recordId,
        syndromeId: active.syndromeId,
        originalQuote: active.originalQuote,
        constraint: active.constraint,
        submissionResult: active.submissionResult as unknown,
        status: active.status,
        startedAt: active.startedAt,
        updatedAt: active.updatedAt,
        completedAt: active.completedAt,
      };
      return response;
    },
  );
}

/**
 * 领域对象 → IPC 响应(共享转换逻辑)
 * - start/advanceStep/updateDraft/evaluate/complete/abort 事件都需要此映射
 * - 提取为独立函数确保一致性
 */
function activeTrainingToResponse(active: ActiveTraining): ActiveTrainingGetResponse {
  return {
    sessionId: active.sessionId,
    challengeId: active.challengeId,
    challengeName: active.challengeName,
    mode: active.mode,
    currentStepIndex: active.currentStepIndex,
    steps: active.steps,
    userDraft: active.userDraft,
    flowType: active.flowType,
    trainingFlow: active.trainingFlow,
    recordId: active.recordId,
    syndromeId: active.syndromeId,
    originalQuote: active.originalQuote,
    constraint: active.constraint,
    submissionResult: active.submissionResult as unknown,
    status: active.status,
    startedAt: active.startedAt,
    updatedAt: active.updatedAt,
    completedAt: active.completedAt,
  };
}

/**
 * Sprint 24 A-4: 桥接 ActiveTrainingService 状态变更到 renderer
 *
 * 工作流:
 *   1. 订阅 ActiveTrainingService.onStateChange()
 *   2. 收到事件后通过 mainWindow.webContents.send() 推送到渲染进程
 *   3. 推送到 BrowserWindow.getAllWindows()(多窗口场景都同步)
 *
 * 异常隔离:
 *   - 主窗口为 null 或已销毁时静默跳过
 *   - service 未初始化时静默跳过(开发期)
 *
 * @returns 取消订阅函数(测试清理用)
 */
export function setupActiveTrainingPush(
  mainWindow: BrowserWindow | null,
): () => void {
  if (!activeTrainingService) {
    console.warn(
      '[ActiveTrainingIPC] setupActiveTrainingPush: service not initialized, push disabled',
    );
    return () => {};
  }

  const off = activeTrainingService.onStateChange((event) => {
    const payload: ActiveTrainingUpdatedEvent = {
      type: event.type as ActiveTrainingStateChangeType,
      sessionId: event.sessionId,
      state: activeTrainingToResponse(event.state),
    };

    // 多窗口广播(包含主窗口)
    const windows = BrowserWindow.getAllWindows();
    for (const win of windows) {
      if (win.isDestroyed()) continue;
      const wc = win.webContents;
      if (wc.isDestroyed()) continue;
      try {
        wc.send(IPC_CHANNELS.ACTIVE_TRAINING_UPDATED, payload);
      } catch (err) {
        console.error(
          `[ActiveTrainingIPC] failed to push to window ${wc.id}:`,
          err,
        );
      }
    }

    // 显式 mainWindow 单独再发一次(防止 webContents 列表时序问题)
    if (mainWindow && !mainWindow.isDestroyed() && !mainWindow.webContents.isDestroyed()) {
      try {
        mainWindow.webContents.send(IPC_CHANNELS.ACTIVE_TRAINING_UPDATED, payload);
      } catch {
        // 已通过 getAllWindows 处理,此处静默
      }
    }
  });

  return off;
}

