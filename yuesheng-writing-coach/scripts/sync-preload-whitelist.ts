/**
 * preload 白名单同步脚本
 *
 * 从 shared/constants.ts 的 ALLOWED_INVOKE_CHANNELS 和 ALLOWED_EVENT_CHANNELS
 * 同步到 preload/index.ts，消除手工维护的白名单差异。
 *
 * 用法：npx tsx scripts/sync-preload-whitelist.ts
 */

import * as fs from 'fs';
import * as path from 'path';

const PRELOAD_PATH = path.join(__dirname, '..', 'src', 'preload', 'index.ts');
const CONSTANTS_PATH = path.join(__dirname, '..', 'src', 'shared', 'constants.ts');

/** 从 IPC_CHANNELS 对象定义中提取 key → value 映射 */
function extractChannelMap(content: string): Record<string, string> {
  const map: Record<string, string> = {};
  // 匹配 IPC_CHANNELS = { ... } 或 IPC_CHANNELS: { ... } 定义块中的 KEY: 'value' 条目
  const blockMatch = content.match(/export const IPC_CHANNELS\s*=\s*\{([\s\S]*?)\}\s*(?:as\s+const)?;/);
  if (!blockMatch) throw new Error('找不到 IPC_CHANNELS 定义');
  const block = blockMatch[1];
  const entryRegex = /(\w+)\s*:\s*'([^']+)'/g;
  let m;
  while ((m = entryRegex.exec(block)) !== null) {
    map[m[1]] = m[2];
  }
  return map;
}

/** 从 ALLOWED_*_CHANNELS 数组中提取 IPC_CHANNELS.KEY 模式中的 KEY 列表 */
function extractChannelKeys(content: string, variableName: string): string[] {
  const regex = new RegExp(
    `export\\s+const\\s+${variableName}\\s*:\\s*(?:readonly\\s*)?string\\[\\]\\s*=\\s*\\[([\\s\\S]*?)\\];`
  );
  const match = content.match(regex);
  if (!match) throw new Error(`找不到 ${variableName} 定义`);

  const body = match[1];
  const keys: string[] = [];
  const keyRegex = /IPC_CHANNELS\.(\w+)/g;
  let m;
  while ((m = keyRegex.exec(body)) !== null) {
    keys.push(m[1]);
  }
  return keys;
}

function main(): void {
  const constantsContent = fs.readFileSync(CONSTANTS_PATH, 'utf-8');
  const preloadContent = fs.readFileSync(PRELOAD_PATH, 'utf-8');

  // 建立 IPC_CHANNELS.key → actualValue 映射
  const channelMap = extractChannelMap(constantsContent);

  // 提取白名单中的 key 列表
  const invokeKeys = extractChannelKeys(constantsContent, 'ALLOWED_INVOKE_CHANNELS');
  const eventKeys = extractChannelKeys(constantsContent, 'ALLOWED_EVENT_CHANNELS');

  // 使用实际 channel value，而非 kebab-case
  const invokeChannels = invokeKeys.map(k => {
    if (!channelMap[k]) throw new Error(`IPC_CHANNELS 中未定义 ${k}`);
    return channelMap[k];
  });
  const eventChannels = eventKeys.map(k => {
    if (!channelMap[k]) throw new Error(`IPC_CHANNELS 中未定义 ${k}`);
    return channelMap[k];
  });

  // Check if the channel lists match
  const currentInvokeMatch = preloadContent.match(/const allowedInvokeChannels: readonly string\[\] = \[([\s\S]*?)\];/);
  const currentEventMatch = preloadContent.match(/const allowedEventChannels: readonly string\[\] = \[([\s\S]*?)\];/);
  const currentSendMatch = preloadContent.match(/const allowedSendChannels: readonly string\[\] = \[([\s\S]*?)\];/);

  if (!currentInvokeMatch || !currentEventMatch) {
    console.error('❌ preload/index.ts 格式异常，无法自动同步');
    process.exit(1);
  }

  const expectedInvoke = invokeChannels.map(c => `  '${c}'`).join(',\n');
  const expectedEvent = eventChannels.map(c => `  '${c}'`).join(',\n');

  const newPreload = preloadContent
    .replace(
      /const allowedInvokeChannels: readonly string\[\] = \[[\s\S]*?\];/,
      `const allowedInvokeChannels: readonly string[] = [\n${expectedInvoke},\n];`
    )
    .replace(
      /const allowedEventChannels: readonly string\[\] = \[[\s\S]*?\];/,
      `const allowedEventChannels: readonly string[] = [\n${expectedEvent},\n];`
    );

  const changed = newPreload !== preloadContent;

  if (changed) {
    fs.writeFileSync(PRELOAD_PATH, newPreload, 'utf-8');
    console.log('✅ preload 白名单已同步');
  } else {
    console.log('✅ preload 白名单已是最新，无需同步');
  }

  // Output diff info
  console.log(`\nInvoke channels: ${invokeChannels.length}`);
  console.log(`Event channels: ${eventChannels.length}`);
}

main();
