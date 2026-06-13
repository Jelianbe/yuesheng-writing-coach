/**
 * 前端 Services 层统一导出
 *
 * 各域服务封装 IPC 通信细节，提供类型化的调用接口。
 * 组件和 Store 通过此入口导入服务，不直接访问 window.electronAPI。
 */

export { typedInvoke, typedOn } from './ipc-client';
export type { AppController, AppControllerCallbacks } from './app-controller';
export { createAppController } from './app-controller';
export { useAppController } from './useAppController';
export { chatService } from './chat.service';
export { diagnosisService } from './diagnosis.service';
export { teachingStateService } from './teaching-state.service';
export { trainingService } from './training.service';
export { sessionService } from './session.service';
export { studentContextService } from './student-context.service';
export { rightPanelService } from './right-panel.service';
export type { PanelId } from './right-panel.service';
