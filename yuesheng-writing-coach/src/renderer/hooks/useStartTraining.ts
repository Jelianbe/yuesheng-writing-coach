import { useCallback } from 'react';
import { useSessionStore } from '../stores/session.store';
import { useUiStore } from '../stores/ui.store';
import { serviceBridge } from '../services/service-bridge';

interface TechniqueInfo {
  id: string;
  name: string;
  difficulty: string;
  category: string;
  description: string;
  coreName: string;
}

interface TrainingCatalogGroup {
  coreId: string;
  coreName: string;
  count: number;
  techniques: Array<{
    id: string;
    name: string;
    difficulty: string;
    category: string;
    description: string;
  }>;
}

interface TrainingCatalogResponse {
  groups: TrainingCatalogGroup[];
  total: number;
}

/**
 * 从后端加载技法目录，通过技法名称查找对应信息
 */
async function findTechniqueByName(name: string): Promise<TechniqueInfo | null> {
  try {
    const data = await serviceBridge.invoke<Record<string, never>, TrainingCatalogResponse>(
      'training:catalog',
      {},
    );
    if (!data?.groups) return null;
    for (const g of data.groups) {
      const found = g.techniques.find(t => t.name === name);
      if (found) {
        return { ...found, coreName: g.coreName };
      }
    }
    return null;
  } catch {
    console.warn('[useStartTraining] IPC training:catalog failed');
    return null;
  }
}

export const useStartTraining = () => {
  return useCallback(async (techniqueName: string) => {
    // 1. 从后端获取技法信息
    const techInfo = await findTechniqueByName(techniqueName);
    if (!techInfo) {
      console.warn('[useStartTraining] 未找到技法:', techniqueName);
      return;
    }

    // 2. 创建新会话
    const session = await useSessionStore.getState().createSession();
    if (!session) {
      console.warn('[useStartTraining] 创建会话失败');
      return;
    }

    // 3. 请求后端分配训练（AI 将生成首条消息）
    try {
      await serviceBridge.invoke<
        { sessionId: string; challengeId: string },
        { record?: { id: string } }
      >('training:assign', {
        sessionId: session.id,
        challengeId: techInfo.id,
      });
    } catch (e) {
      console.warn('[useStartTraining] training:assign 失败，使用空会话', e);
    }

    // 4. 设置训练上下文 UI 状态
    useUiStore.getState().setTrainingContext(session.id, {
      techniqueName: techInfo.name,
      category: techInfo.category,
      difficulty: techInfo.difficulty as 'beginner' | 'intermediate' | 'advanced',
      description: techInfo.description,
      coreName: techInfo.coreName,
    });

    // 5. 切换到对话 tab
    useUiStore.getState().setLeftTab('chat');
  }, []);
};
