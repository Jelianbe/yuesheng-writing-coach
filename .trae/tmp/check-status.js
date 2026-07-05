// 检查模拟器/ADB 状态
const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const userProfile = process.env.USERPROFILE;
const ANDROID_HOME = path.join(userProfile, 'AppData', 'Local', 'Android', 'Sdk');
const adb = path.join(ANDROID_HOME, 'platform-tools', 'adb.exe');
const emulator = path.join(ANDROID_HOME, 'emulator', 'emulator.exe');

console.log('=== adb 设备 ===');
try {
  const out = execSync(`"${adb}" devices -l`, { encoding: 'utf8' });
  console.log(out);
} catch (e) {
  console.error('adb devices 失败:', e.message);
}

console.log('\n=== 模拟器进程 ===');
try {
  const out = execSync('tasklist /FI "IMAGENAME eq emulator.exe"', { encoding: 'utf8' });
  console.log(out);
} catch (e) {}

console.log('\n=== 模拟器 qemu 进程 ===');
try {
  const out = execSync('tasklist /FI "IMAGENAME eq qemu-system-x86_64.exe"', { encoding: 'utf8' });
  console.log(out);
} catch (e) {}

console.log('\n=== boot_completed ===');
try {
  const out = execSync(`"${adb}" -s emulator-5554 shell getprop sys.boot_completed 2>&1`, { encoding: 'utf8' });
  console.log('boot_completed =', out.trim());
} catch (e) {
  console.log('检查失败:', e.message.slice(0, 200));
}
