// Testing Library 设置
// 在运行每个测试文件之前自动执行，扩展 Vitest 的匹配器
import '@testing-library/jest-dom/vitest';

// Sprint 26 阶段 3.1+ 双轨改造:
// 防止 @capacitor/core 在 jsdom 环境自动注入 window.Capacitor,导致 isCapacitor() 误判为 true
// (测试中应强制走 electron 路径,mock typedInvoke,避免触发 CapacitorSqliteAdapter 初始化失败)
delete (window as unknown as { Capacitor?: unknown }).Capacitor;
