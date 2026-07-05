/**
 * ActiveTraining — Sprint 26 阶段 3.5 方案 4a bridge 注册
 *
 * 原 IPC handler 已废弃,改为 registerMethod 走单端点 bridge:invoke。
 * 调用方:`serviceBridge.invoke('activeTraining:updateDraft' | 'activeTraining:submitStep' | 'activeTraining:get', ...)`
 *
 * 依赖: ActiveTrainingService (DI 注入)
 *
 * 保留 export 函数(被 ipc-registry 调用):
 * - setupActiveTrainingPush(mainWindow): 订阅 Service 状态变更并广播到所有窗口
 * - activeTrainingToResponse: 领域对象 → IPC 响应映射(供 setupActiveTrainingPush 使用)
 *
 * 异常隔离: 训练已 completed/aborted 时静默返回
 */

import { BrowserWindow } from 'electron';
import { IPC_CHANNELS } from '../../shared/constants';
import { validatePayload } from './utils/validate-payload';
import { registerMethod } from '../core/service-bridge';
import type { ActiveTrainingService } from '../domains/03-teaching/state/active-training.service';
import type {
  ActiveTrainingUpdateDraftResponse,
  ActiveTrainingGetResponse,
  ActiveTrainingUpdatedEvent,
  ActiveTrainingStateChangeType,
  ActiveTrainingSubmitStepResponse,
  ActiveTrainingGetDraftSnapshotsResponse,
  ActiveTrainingRestoreDraftSnapshotResponse,
} from '../../shared/api-contracts/active-training.contract';
import type { ActiveTraining } from '../domains/03-teaching/state/active-training.types';

let activeTrainingService: ActiveTrainingService | null = null;

export function initActiveTrainingHandlers(service: ActiveTrainingService): void {
  activeTrainingService = service;
}

function getService(): ActiveTrainingService {
  if (!activeTrainingService) {
    throw new Error(
      '[ActiveTrainingIPC] ActiveTrainingService not initialized. Call initActiveTrainingHandlers() first.',
    );
  }
  return activeTrainingService;
}

export function activeTrainingToResponse(active: ActiveTraining): ActiveTrainingGetResponse {
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
    stepResponses: active.stepResponses,
    status: active.status,
    startedAt: active.startedAt,
    updatedAt: active.updatedAt,
    completedAt: active.completedAt,
  };
}

export function registerActiveTrainingHandlers(): void {
  registerMethod('activeTraining:updateDraft', async (args) => {
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
    } satisfies ActiveTrainingUpdateDraftResponse;
  });

  registerMethod('activeTraining:submitStep', async (args) => {
    const validation = validatePayload<{
      sessionId: string;
      stepId: 1 | 2 | 3 | 4 | 5;
      content: string;
    }>(args, {
      required: ['sessionId', 'stepId', 'content'],
      types: { sessionId: 'string', stepId: 'number', content: 'string' },
    });
    if (!validation.valid) {
      throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    }

    const { sessionId, stepId, content } = validation.data;
    const service = getService();
    const updated = service.submitFlowStep(sessionId, stepId, content);

    if (!updated) {
      return {
        success: false,
        submittedCount: 0,
        submittedAt: new Date().toISOString(),
        status: service.getStatus(sessionId),
      };
    }

    return {
      success: true,
      submittedCount: updated.stepResponses.length,
      submittedAt:
        updated.stepResponses.find((r) => r.stepId === stepId)?.submittedAt ??
        new Date().toISOString(),
      status: updated.status,
    } satisfies ActiveTrainingSubmitStepResponse;
  });

  registerMethod('activeTraining:get', async (args) => {
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

    return activeTrainingToResponse(active);
  });

  registerMethod('activeTraining:getDraftSnapshots', async (args) => {
    const validation = validatePayload<{ activeTrainingId: number }>(args, {
      required: ['activeTrainingId'],
      types: { activeTrainingId: 'number' },
    });
    if (!validation.valid) {
      throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    }

    const service = getService();
    const snapshots = service.getDraftSnapshots(validation.data.activeTrainingId);
    return { snapshots } satisfies ActiveTrainingGetDraftSnapshotsResponse;
  });

  registerMethod('activeTraining:restoreDraftSnapshot', async (args) => {
    const validation = validatePayload<{ activeTrainingId: number; snapshotId: number }>(args, {
      required: ['activeTrainingId', 'snapshotId'],
      types: { activeTrainingId: 'number', snapshotId: 'number' },
    });
    if (!validation.valid) {
      throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    }

    const service = getService();
    const restored = service.restoreDraftSnapshot(
      validation.data.activeTrainingId,
      validation.data.snapshotId,
    );
    return {
      success: restored !== null,
      restoredSnapshot: restored,
    } satisfies ActiveTrainingRestoreDraftSnapshotResponse;
  });
}

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
