// 用 TCG 软件加速(完全无硬件加速)启动
const { execSync, spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const userProfile = process.env.USERPROFILE;
const ANDROID_HOME = path.join(userProfile, 'AppData', 'Local', 'Android', 'Sdk');
const emulator = path.join(ANDROID_HOME, 'emulator', 'emulator.exe');
const adb = path.join(ANDROID_HOME, 'platform-tools', 'adb.exe');

function run(cmd) {
  console.log(`\n$ ${cmd}`);
  try { return execSync(cmd, { encoding: 'utf8', stdio: 'inherit' }); }
  catch (e) { return null; }
}

console.log('=== 1. 杀掉所有 ===');
try { execSync('taskkill /F /IM emulator.exe /T', { stdio: 'inherit' }); } catch (e) {}
try { execSync('taskkill /F /IM qemu-system-x86_64-headless.exe /T', { stdio: 'inherit' }); } catch (e) {}
run(`"${adb}" kill-server`);

console.log('\n=== 2. 启动 AVD (TCG 软件加速) ===');
const proc = spawn(emulator, [
  '-avd', 'Pixel6',
  '-no-window',
  '-no-audio',
  '-no-boot-anim',
  '-no-snapshot',
  '-accel', 'off',                       // 关闭硬件加速 → TCG
  '-gpu', 'swiftshader_indirect',
  '-memory', '2048',
  '-cores', '2',
  '-netdelay', 'none',
  '-netspeed', 'full',
  '-wipe-data',
], {
  stdio: ['ignore', 'pipe', 'pipe'],
  env: { ...process.env, ANDROID_HOME, ANDROID_SDK_ROOT: ANDROID_HOME },
  windowsHide: true,
});

console.log('PID:', proc.pid);

proc.stdout.on('data', (d) => process.stdout.write('[EMU] ' + d));
proc.stderr.on('data', (d) => process.stderr.write('[EMU!] ' + d));

proc.on('close', (code) => console.log(`\n[exit] code=${code}`));
proc.on('error', (e) => console.error('[err]:', e));
