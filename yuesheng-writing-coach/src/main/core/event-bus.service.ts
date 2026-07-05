/**
 * EventBus — 主进程侧中央事件总线(Sprint 20 Issue 20-1 B-1)
 *
 * 设计目标:
 * - 主进程内模块间解耦:发布者不知道订阅者
 * - 类型安全:DomainEvent 联合类型,handler 必须 match
 * - 可测试:支持 mock / 注入
 * - 可观测:emit 记录到 log,生产环境可挂 tracing
 *
 * 范围:
 * - 主进程内部 bus(同进程内模块间)
 * - 通过 ipcBridge 暴露给 renderer
 * - 不取代 request-response typedInvoke,只取代 event 通道
 *
 * 依据: dev-docs/tasks/sprint-20-plan.md §B-1
 */

/** 领域事件联合类型 — 所有事件在此声明 */
export type DomainEvent =
  // 会话层
  | { topic: 'chat:token'; payload: { sessionId: string; content: string } }
  | { topic: 'chat:intent'; payload: { sessionId: string; intent: unknown } }
  | { topic: 'chat:phase_transition'; payload: { sessionId: string; from: string; to: string } }
  | { topic: 'chat:done'; payload: { sessionId: string } }
  | { topic: 'chat:error'; payload: { sessionId: string; code: string; message: string } }
  // 诊断层
  | { topic: 'diagnosis:extracted'; payload: { sessionId: string; syndromeId: string; severity: 'L1' | 'L2' | 'L3' | null } }
  | { topic: 'diagnosis:result'; payload: { sessionId: string; problemId: string | null } }
  // 训练层
  | { topic: 'training:triggered'; payload: { sessionId: string; syndromeId: string; techniqueId?: string } }
  | { topic: 'training:step'; payload: { sessionId: string; step: number; totalSteps: number } }
  | { topic: 'training:completed'; payload: { sessionId: string } };

/** 事件主题联合类型 */
export type DomainEventTopic = DomainEvent['topic'];

/** 事件 payload 提取 */
export type PayloadOf<T extends DomainEventTopic> = Extract<DomainEvent, { topic: T }>['payload'];

/** 订阅 handler */
export type EventHandler<T extends DomainEventTopic> = (payload: PayloadOf<T>) => void | Promise<void>;

/** 取消订阅函数 */
export type Unsubscribe = () => void;

interface Subscription<T extends DomainEventTopic = DomainEventTopic> {
  topic: T;
  handler: EventHandler<T>;
  id: string;
}

/**
 * 事件总线实现
 *
 * 使用模式:
 * ```ts
 * const bus = new EventBus();
 * const off = bus.on('chat:token', (payload) => console.log(payload.content));
 * bus.emit({ topic: 'chat:token', payload: { sessionId: 's1', content: 'hi' } });
 * off();
 * ```
 */
export class EventBus {
  private subscriptions: Map<DomainEventTopic, Subscription[]> = new Map();
  private idCounter = 0;
  /** 测试钩子,记录 emit 历史 */
  public readonly emittedLog: DomainEvent[] = [];

  /**
   * 订阅主题
   * 同一 handler 多次订阅同一 topic 会注册多次(行为符合 EventEmitter)
   */
  on<T extends DomainEventTopic>(topic: T, handler: EventHandler<T>): Unsubscribe {
    const id = `${topic}-${++this.idCounter}`;
    const sub: Subscription<T> = { topic, handler, id };
    const list = this.subscriptions.get(topic) ?? [];
    list.push(sub as unknown as Subscription);
    this.subscriptions.set(topic, list);
    return () => this.offById(id);
  }

  /**
   * 取消所有订阅(测试清理用)
   */
  removeAllListeners(topic?: DomainEventTopic): void {
    if (topic) {
      this.subscriptions.delete(topic);
    } else {
      this.subscriptions.clear();
    }
  }

  /**
   * 发射事件 — 同步派发所有订阅者
   * handler 抛错不阻断其他订阅者,错误会 console.error
   */
  emit(event: DomainEvent): void {
    this.emittedLog.push(event);
    const list = this.subscriptions.get(event.topic);
    if (!list) return;
    // 复制一份避免 handler 内部 off 影响本次派发
    for (const sub of [...list]) {
      try {
        const result = sub.handler(event.payload);
        if (result instanceof Promise) {
          result.catch((err) => {
            console.error(`[EventBus] async handler error on ${event.topic}:`, err);
          });
        }
      } catch (err) {
        console.error(`[EventBus] sync handler error on ${event.topic}:`, err);
      }
    }
  }

  /**
   * 异步发射(等待所有 handler 完成)
   * 用于需要保证副作用完成的场景(如落库)
   */
  async emitAndWait(event: DomainEvent): Promise<void> {
    this.emittedLog.push(event);
    const list = this.subscriptions.get(event.topic);
    if (!list) return;
    await Promise.all(
      list.map(sub =>
        Promise.resolve(sub.handler(event.payload)).catch((err) => {
          console.error(`[EventBus] handler error on ${event.topic}:`, err);
        }),
      ),
    );
  }

  private offById(id: string): void {
    for (const [topic, list] of this.subscriptions) {
      const idx = list.findIndex(s => s.id === id);
      if (idx >= 0) {
        list.splice(idx, 1);
        if (list.length === 0) this.subscriptions.delete(topic);
        return;
      }
    }
  }

  /** 测试用,获取当前订阅数 */
  listenerCount(topic: DomainEventTopic): number {
    return this.subscriptions.get(topic)?.length ?? 0;
  }
}

/** 全局单例(主进程使用) */
let globalBus: EventBus | null = null;

export function getGlobalEventBus(): EventBus {
  if (!globalBus) globalBus = new EventBus();
  return globalBus;
}

/** 测试重置 */
export function resetGlobalEventBus(): void {
  globalBus?.removeAllListeners();
  globalBus = null;
}
