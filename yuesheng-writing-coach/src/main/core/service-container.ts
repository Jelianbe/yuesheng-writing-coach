/**
 * 轻量级依赖注入容器
 * 负责：管理服务的创建和依赖关系，替代手动 setter 调用
 * 特性：单例模式、延迟初始化、循环依赖检测
 */

export type Factory<T> = (container: ServiceContainer) => T;

export class ServiceContainer {
  private services = new Map<string, unknown>();
  private factories = new Map<string, Factory<unknown>>();
  private resolving = new Set<string>();

  register<T>(name: string, factory: Factory<T>): void {
    this.factories.set(name, factory as Factory<unknown>);
  }

  get<T>(name: string): T {
    if (this.services.has(name)) {
      return this.services.get(name) as T;
    }

    if (this.resolving.has(name)) {
      throw new Error(`Circular dependency detected: ${name}`);
    }

    const factory = this.factories.get(name);
    if (!factory) {
      throw new Error(`Service not registered: ${name}`);
    }

    this.resolving.add(name);
    try {
      const instance = factory(this);
      this.services.set(name, instance);
      return instance as T;
    } finally {
      this.resolving.delete(name);
    }
  }

  has(name: string): boolean {
    return this.factories.has(name) || this.services.has(name);
  }

  clear(): void {
    this.services.clear();
    this.factories.clear();
    this.resolving.clear();
  }

  private static instance: ServiceContainer | null = null;

  static getInstance(): ServiceContainer {
    if (!ServiceContainer.instance) {
      ServiceContainer.instance = new ServiceContainer();
    }
    return ServiceContainer.instance;
  }

  static reset(): void {
    if (ServiceContainer.instance) {
      ServiceContainer.instance.clear();
      ServiceContainer.instance = null;
    }
  }
}
