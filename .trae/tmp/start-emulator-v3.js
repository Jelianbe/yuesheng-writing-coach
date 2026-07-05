// 启动 AVD 模拟器 - 简化参数 + 等待 boot
const { spawn, execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const userProfile = process.env.USERPROFILE;
const ANDROID_HOME = path.join(userProfile, 'AppData', 'Local', 'Android', 'Sdk');
const emulator = path.join(ANDROID_HOME, 'emulator', 'emulator.exe');
const adb = path.join(ANDROID_HOME, 'platform-tools', 'adb.exe');

const env = {
  ...process.env,
  ANDROID_HOME,
  ANDROID_SDK_ROOT: ANDROID_HOME,
};

console.log('=== 启动 AVD ===');
console.log('emulator =', emulator);
console.log('emulator 存在:', fs.existsSync(emulator));

// 启动模拟器 (带窗口 - 让它能正常报告 boot completed)
const proc = spawn(emulator, [
  '-avd', 'Pixel6',
  '-no-window',          // headless 模式
  '-no-audio',
  '-no-boot-anim',       // 跳过启动动画
  '-no-snapshot',        // 不使用快照
  '-gpu', 'swiftshader_indirect',
  '-accel', 'auto',
  '-netdelay', 'none',
  '-netspeed', 'full',
], {
  stdio: ['ignore', 'pipe', 'pipe'],
  env,
  windowsHide: true,
});

console.log(`模拟器进程已启动, PID: ${proc.pid}`);

let bootCompleted = false;
let errorOutput = '';
proc.stdout.on('data', (d) => process.stdout.write('[EMU] ' + d));
proc.stderr.on('data', (d) => {
  errorOutput += d.toString();
  process.stderr.write('[EMU!] ' + d);
});

proc.on('close', (code) => console.log(`\n[模拟器退出] code=${code}`));
proc.on('error', (e) => console.error('[spawn error]:', e));

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function waitBoot() {
  console.log('\n=== 等待设备就绪 ===');
  // 阶段 1: 等 emulator 进程出现 + adb 看到设备
  for (let i = 0; i < 60; i++) {
    await sleep(3000);
    try {
      const out = execSync(`"${adb}" devices`, { encoding: 'utf8' });
      const lines = out.trim().split('\n').filter(l => l.includes('emulator') || l.includes('device') || l.includes('List'));
      const lastLine = lines[lines.length - 1] || '';
      console.log(`[${(i + 1) * 3}s] ${lastLine.trim()}`);

      if (lastLine.includes('device') && !lastLine.includes('offline')) {
        console.log('  -> 设备就绪,等待 boot completed...');
        break;
      }
    } catch (e) {}
  }

  // 阶段 2: 等 boot_completed
  console.log('\n=== 等待 boot_completed ===');
  for (let i = 0; i < 90; i++) {
    await sleep(3000);
    try {
      const out = execSync(`"${adb}" -s emulator-5554 shell getprop sys.boot_completed 2>&1`, { encoding: 'utf8' });
      const status = out.trim();
      console.log(`[${(i + 1) * 3}s] boot_completed = ${status}`);
      if (status === '1') {
        bootCompleted = true;
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
    console.log('\n[OK] 模拟器就绪');
  } else {
    console.error('\n[FAIL] 启动超时');
    console.log('最后错误输出:', errorOutput.slice(-1000));
  }
});
