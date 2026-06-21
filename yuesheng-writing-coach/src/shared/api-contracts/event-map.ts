// ─── 事件通道类型映射 ───
// IPCRenderer.on(channel, callback) 时 callback 参数的类型推导入口

import type { ChatStreamDataEvent, ChatStreamEndEvent, ChatToolExecutingEvent } from './chat.contract';
import type { DiagnosisUpdateEvent } from './diagnosis.contract';
import type { TeachingStateUpdatedEvent, TeachingStateMasteryEvent } from './teaching-state.contract';

/** 事件通道 → 事件负载类型的映射 */
export interface EventChannelMap {
  'chat:stream:data': ChatStreamDataEvent;
  'chat:stream:end': ChatStreamEndEvent;
  'chat:tool:executing': ChatToolExecutingEvent;
  'diagnosis:updated': DiagnosisUpdateEvent;
  'teachingState:updated': TeachingStateUpdatedEvent;
  'teachingState:mastery': TeachingStateMasteryEvent;
}

/** 所有事件通道的联合类型 */
export type EventChannel = keyof EventChannelMap;

/** 根据事件通道获取对应的事件负载类型 */
export type EventPayload<C extends EventChannel> = EventChannelMap[C];
