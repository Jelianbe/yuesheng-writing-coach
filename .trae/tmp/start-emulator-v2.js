// 启动 AVD 模拟器 - 详细日志模式
const { spawn, execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const userProfile = process.env.USERPROFILE;
const ANDROID_HOME = path.join(userProfile, 'AppData', 'Local', 'Android', 'Sdk');
const JAVA_HOME = 'C:\\Program Files\\Android\\Android Studio\\jbr';
const emulator = path.join(ANDROID_HOME, 'emulator', 'emulator.exe');
const adb = path.join(ANDROID_HOME, 'platform-tools', 'adb.exe');

const env = {
  ...process.env,
  ANDROID_HOME,
  ANDROID_SDK_ROOT: ANDROID_HOME,
  JAVA_HOME,
};

console.log('=== 启动 AVD (带详细日志) ===');

const proc = spawn(emulator, [
  '-avd', 'Pixel6',
  '-no-window',
  '-no-audio',
  '-no-boot-anim',
  '-no-snapshot',
  '-gpu', 'swiftshader_indirect',
  '-accel', 'auto',
  '-verbose',
], {
  stdio: ['ignore', 'pipe', 'pipe'],
  env,
  windowsHide: true,
});

proc.stdout.on('data', (d) => process.stdout.write('[EMU OUT] ' + d));
proc.stderr.on('data', (d) => process.stderr.write('[EMU ERR] ' + d));

proc.on('close', (code) => console.log(`\n[模拟器退出] code=${code}`));
proc.on('error', (e) => console.error('[spawn error]:', e));

// 5秒后检查进程是否还活着
setTimeout(() => {
  try {
    const out = execSync('tasklist /FI "IMAGENAME eq emulator.exe" /FO CSV /NH', { encoding: 'utf8' });
    console.log('\n[5s 后] emulator.exe 状态:', out.trim() || '未运行');
  } catch (e) {}
  try {
    const out = execSync('tasklist /FI "IMAGENAME eq qemu-system-x86_64.exe" /FO CSV /NH', { encoding: 'utf8' });
    console.log('[5s 后] qemu 状态:', out.trim() || '未运行');
  } catch (e) {}
  try {
    const out = execSync(`"${adb}" devices`, { encoding: 'utf8' });
    console.log('[5s 后] adb devices:', out.trim());
  } catch (e) {}
}, 5000);

setTimeout(() => {
  try {
    const out = execSync('tasklist /FI "IMAGENAME eq emulator.exe" /FO CSV /NH', { encoding: 'utf8' });
    console.log('\n[15s 后] emulator.exe 状态:', out.trim() || '未运行');
  } catch (e) {}
  try {
    const out = execSync(`"${adb}" devices`, { encoding: 'utf8' });
    console.log('[15s 后] adb devices:', out.trim());
  } catch (e) {}
}, 15000);

setTimeout(() => {
  console.log('\n[30s 后] 继续监控...');
  try {
    const out = execSync(`"${adb}" devices`, { encoding: 'utf8' });
    console.log('[30s 后] adb devices:', out.trim());
  } catch (e) {}
  // 让脚本继续运行
}, 30000);
