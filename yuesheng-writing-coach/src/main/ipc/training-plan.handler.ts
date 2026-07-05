/**
 * 训练计划 IPC Handler — Sprint 38
 *
 * 通过 service-bridge 的 registerMethod/registerMethods 注册 plan:* 通道。
 * 调用方: serviceBridge.invoke('plan:create' | ...)
 */
import { registerMethods } from '../core/service-bridge';
import { validatePayload } from './utils/validate-payload';
import type { TrainingPlanService } from '../domains/04-validation/training-plan/training-plan.service';

export function initTrainingPlanHandlers(service: TrainingPlanService): void {
  registerMethods([
    {
      method: 'plan:create',
      handler: async (args: unknown) => {
        const v = validatePayload<{ name: string; description?: string }>(args, {
          required: ['name'],
          types: { name: 'string', description: 'string' },
        });
        if (!v.valid) throw new Error(`INVALID_PAYLOAD: ${v.error.message}`);
        return service.create(v.data.name, v.data.description ?? '');
      },
    },
    {
      method: 'plan:list',
      handler: async () => {
        return service.list();
      },
    },
    {
      method: 'plan:get',
      handler: async (args: unknown) => {
        const v = validatePayload<{ planId: string }>(args, {
          required: ['planId'],
          types: { planId: 'string' },
        });
        if (!v.valid) throw new Error(`INVALID_PAYLOAD: ${v.error.message}`);
        return service.get(v.data.planId);
      },
    },
    {
      method: 'plan:delete',
      handler: async (args: unknown) => {
        const v = validatePayload<{ planId: string }>(args, {
          required: ['planId'],
          types: { planId: 'string' },
        });
        if (!v.valid) throw new Error(`INVALID_PAYLOAD: ${v.error.message}`);
        service.delete(v.data.planId);
        return { success: true };
      },
    },
    {
      method: 'plan:addItem',
      handler: async (args: unknown) => {
        const v = validatePayload<{ planId: string; challengeId: string }>(args, {
          required: ['planId', 'challengeId'],
          types: { planId: 'string', challengeId: 'string' },
        });
        if (!v.valid) throw new Error(`INVALID_PAYLOAD: ${v.error.message}`);
        return service.addItem(v.data.planId, v.data.challengeId);
      },
    },
    {
      method: 'plan:removeItem',
      handler: async (args: unknown) => {
        const v = validatePayload<{ planId: string; itemId: string }>(args, {
          required: ['planId', 'itemId'],
          types: { planId: 'string', itemId: 'string' },
        });
        if (!v.valid) throw new Error(`INVALID_PAYLOAD: ${v.error.message}`);
        service.removeItem(v.data.planId, v.data.itemId);
        return { success: true };
      },
    },
    {
      method: 'plan:updateItemStatus',
      handler: async (args: unknown) => {
        const v = validatePayload<{ itemId: string; status: string }>(args, {
          required: ['itemId', 'status'],
          types: { itemId: 'string', status: 'string' },
        });
        if (!v.valid) throw new Error(`INVALID_PAYLOAD: ${v.error.message}`);
        const validStatuses = ['pending', 'in_progress', 'completed'] as const;
        if (!validStatuses.includes(v.data.status as typeof validStatuses[number])) {
          throw new Error(`INVALID_PAYLOAD: status must be one of ${validStatuses.join(', ')}`);
        }
        service.updateItemStatus(v.data.itemId, v.data.status as 'pending' | 'in_progress' | 'completed');
        return { success: true };
      },
    },
    {
      method: 'plan:getAvailableChallenges',
      handler: async () => {
        return service.getAvailableChallenges();
      },
    },
  ]);
}
