/**
 * PageStackRouter — 移动端页面栈路由
 *
 * 架构：
 * - 375px 容器（clamp(320px, 100%, 375px)），桌面端居中
 * - TabBar 3 tab：书架 | 对话 | 应用
 * - 子页面（project-space / chat）push 进入，TabBar 隐藏
 */

import React from 'react';
import { usePageStackStore } from '../stores/page-stack.store';
import { TabBar } from '../components/navigation/TabBar';
import { BookshelfPage } from '../pages/BookshelfPage';
import { ConversationsPage } from '../pages/ConversationsPage';
import { AppsPage } from '../pages/AppsPage';
import { ProjectSpacePage } from '../pages/ProjectSpacePage';
import { ChatPage } from '../pages/ChatPage';
import { GrowthReportPage } from '../pages/GrowthReportPage';
import { TrainingPlanPage } from '../pages/TrainingPlanPage';
import { TechniqueLibraryPage } from '../pages/TechniqueLibraryPage';
import { MaterialLibraryPage } from '../pages/MaterialLibraryPage';

const PAGE_MAP: Record<string, React.FC<{ params?: Record<string, string> }>> = {
  bookshelf: BookshelfPage,
  conversations: ConversationsPage,
  apps: AppsPage,
  'project-space': ProjectSpacePage,
  chat: ChatPage,
  'growth-report': GrowthReportPage,
  'training-plan': TrainingPlanPage,
  'technique-library': TechniqueLibraryPage,
  'material-library': MaterialLibraryPage,
};

export const PageStackRouter: React.FC = () => {
  const stack = usePageStackStore(s => s.stack);
  const tabBarVisible = usePageStackStore(s => s.tabBarVisible);
  const current = stack[stack.length - 1];
  const PageComponent = PAGE_MAP[current.name];

  if (!PageComponent) {
    return <div style={{ padding: 20, color: 'var(--text-tertiary)' }}>页面未找到</div>;
  }

  return (
    <div style={{
      width: '100%',
      maxWidth: 430,
      height: '100dvh',
      margin: '0 auto',
      display: 'flex',
      flexDirection: 'column',
      background: 'var(--bg-main)',
      overflow: 'hidden',
    }}>
      {/* 主内容区 */}
      <div style={{
        flex: 1,
        overflow: 'hidden auto',
        display: 'flex',
        flexDirection: 'column',
      }}>
        <PageComponent params={current.params} />
      </div>

      {/* TabBar */}
      {tabBarVisible && <TabBar />}
    </div>
  );
};
