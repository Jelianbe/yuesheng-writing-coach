// 启动 AVD 模拟器脚本
const { spawn, execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const userProfile = process.env.USERPROFILE;
const ANDROID_HOME = path.join(userProfile, 'AppData', 'Local', 'Android', 'Sdk');
const JAVA_HOME = 'C:\\Program Files\\Android\\Android Studio\\jbr';
const emulator = path.join(ANDROID_HOME, 'emulator', 'emulator.exe');
const adb = path.join(ANDROID_HOME, 'platform-tools', 'adb.exe');

console.log('ANDROID_HOME =', ANDROID_HOME);
console.log('emulator =', emulator);
console.log('emulator 存在:', fs.existsSync(emulator));

if (!fs.existsSync(emulator)) {
  console.error('emulator.exe 不存在!');
  process.exit(1);
}

const env = {
  ...process.env,
  ANDROID_HOME,
  ANDROID_SDK_ROOT: ANDROID_HOME,
  JAVA_HOME,
};

console.log('\n=== 启动 AVD (headless 后台) ===');
const proc = spawn(emulator, [
  '-avd', 'Pixel6',
  '-no-window',
  '-no-audio',
  '-no-boot-anim',
  '-no-snapshot',
  '-gpu', 'swiftshader_indirect',
  '-accel', 'auto',
], {
  detached: true,
  stdio: 'ignore',
  env,
  windowsHide: true,
});

proc.on('error', (e) => console.error('spawn error:', e));
proc.unref();
console.log(`模拟器进程已启动, PID: ${proc.pid}`);

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function waitBoot() {
  console.log('\n=== 等待 adb 设备就绪 ===');
  for (let i = 0; i < 30; i++) {
    await sleep(2000);
    try {
      const out = execSync(`"${adb}" devices`, { encoding: 'utf8' });
      console.log(`[${i * 2}s] ${out.trim().split('\n').slice(-3).join(' | ')}`);
      if (out.includes('emulator-') && out.includes('device')) {
        console.log('  -> 设备已连接,等待 boot completed...');
        break;
      }
    } catch (e) {}
  }

  console.log('\n=== 等待 boot completed ===');
  for (let i = 0; i < 60; i++) {
    await sleep(3000);
    try {
      const out = execSync(`"${adb}" -s emulator-5554 shell getprop sys.boot_completed`, { encoding: 'utf8' });
      const status = out.trim();
      console.log(`[${(i + 1) * 3}s] boot_completed = ${status}`);
      if (status === '1') {
        console.log('  -> 模拟器启动完成!');
        return true;
      }
    } catch (e) {}
  }
  return false;
}

waitBoot().then(ok => {
  if (ok) {
    console.log('\n=== 设备信息 ===');
    try {
      const info = execSync(`"${adb}" -s emulator-5554 shell "getprop ro.build.version.release; getprop ro.build.version.sdk; getprop ro.product.model"`, { encoding: 'utf8' });
      console.log(info);
    } catch (e) {}
    console.log('\n[OK] 模拟器就绪,等待 APK 安装');
  } else {
    console.error('\n[FAIL] 模拟器启动超时');
  }
});
