// 杀干净 + 重启(更保守参数)
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

console.log('=== 1. 杀掉所有 emulator/qemu ===');
try { execSync('taskkill /F /IM emulator.exe /T', { stdio: 'inherit' }); } catch (e) {}
try { execSync('taskkill /F /IM qemu-system-x86_64-headless.exe /T', { stdio: 'inherit' }); } catch (e) {}
try { execSync('taskkill /F /IM qemu-system-x86_64.exe /T', { stdio: 'inherit' }); } catch (e) {}

console.log('\n=== 2. 杀掉所有 adb 相关 ===');
run(`"${adb}" kill-server`);

console.log('\n=== 3. 清理用户数据 ===');
const userData = path.join(userProfile, '.android', 'avd', 'Pixel6.avd', 'userdata-qemu.img.qcow2');
const userDataInit = path.join(userProfile, '.android', 'avd', 'Pixel6.avd', 'userdata.img');
for (const f of [userData, userDataInit]) {
  if (fs.existsSync(f)) {
    fs.unlinkSync(f);
    console.log('已删除:', f);
  }
}

console.log('\n=== 4. 重启 AVD (关闭 GPU,纯软件) ===');
const proc = spawn(emulator, [
  '-avd', 'Pixel6',
  '-no-window',
  '-no-audio',
  '-no-boot-anim',
  '-no-snapshot',
  '-gpu', 'off',                          // 完全关闭 GPU
  '-accel', 'auto',
  '-memory', '2048',                      // 减少内存
  '-cores', '2',
  '-netdelay', 'none',
  '-netspeed', 'full',
  '-wipe-data',                            // 完全清空
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
