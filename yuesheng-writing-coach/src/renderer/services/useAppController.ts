/**
 * React hook — 应用级编排器
 *
 * 在组件 mount 时自动调用 app-controller 的 initialize()，
 * unmount 时自动调用 destroy() 清理监听。
 *
 * 返回 { ready } 供 App.tsx 判断初始化是否完成。
 */

import { useEffect, useState, useRef } from 'react';
import { createAppController, type AppController } from './app-controller';
import type { AppControllerCallbacks } from './app-controller';

interface UseAppControllerProps {
  /** 新用户引导回调（检测到新用户时触发） */
  setShowOnboarding: (v: boolean) => void;
  /** 流式结束时的回调（如刷新成长汇总） */
  onStreamEnd?: () => void;
}

interface UseAppControllerResult {
  ready: boolean;
}

/**
 * 应用控制器 Hook
 *
 * 替代 App.tsx 中分散的 6 个 store import + 10+ 处 getState() 调用 +
 * useAppIpcListener 的隐式编排。
 *
 * 本 hook 是前端唯一的跨模块协调点。所有跨 store 通信由此统一管理。
 */
export function useAppController({
  setShowOnboarding,
  onStreamEnd,
}: UseAppControllerProps): UseAppControllerResult {
  const [ready, setReady] = useState(false);
  const controllerRef = useRef<AppController | null>(null);

  useEffect(() => {
    const controller = createAppController();
    controllerRef.current = controller;

    const callbacks: AppControllerCallbacks = {
      onStreamEnd,
    };

    try {
      controller.initialize(callbacks);
      setReady(true);
    } catch (err) {
      // eslint-disable-next-line no-console
      console.error('[AppController] init failed:', err);
      setReady(true); // 即使失败也渲染 UI，由子组件处理错误
    }

    return () => {
      controller.destroy();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 新用户检测（原来在 App.tsx 的 useEffect）
  useEffect(() => {
    if (!ready || !window.electronAPI) return;

    import('./session.service').then(({ sessionService }) => {
      sessionService.isNewUser().then((isNew) => {
        if (isNew) setShowOnboarding(true);
      });
    });
  }, [ready, setShowOnboarding]);

  return { ready };
}
