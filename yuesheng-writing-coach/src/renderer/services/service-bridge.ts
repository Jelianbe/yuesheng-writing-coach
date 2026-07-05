/**
 * service-bridge 向后兼容 shim — Sprint 32
 *
 * 保留此文件以免 10+ 个 store/hook 全部需要迁移。
 * 内部委托给 typedInvoke，行为与旧 serviceBridge.invoke 完全一致。
 *
 * 未来 sprint 可逐步将 store 迁移到 invoke() 后删除本文件。
 *
 * 依据: dev-docs/tasks/sprint-32-plan.md
 */
import { typedInvoke } from './ipc-client';

export const serviceBridge = {
  async invoke<TReq, TRes>(channel: string, args: TReq): Promise<TRes | null> {
    try {
      const result = await typedInvoke<{ channel: string; args: TReq }, TRes>(
        'bridge:invoke',
        { channel, args },
      );
      if (!result.success) {
        console.error(`[service-bridge] ${channel}: ${result.error}`);
        return null;
      }
      return result.data ?? null;
    } catch (err) {
      console.error(`[service-bridge] ${channel} failed:`, err);
      return null;
    }
  },
};
