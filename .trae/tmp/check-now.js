// 检查 adb 设备状态
const { execSync } = require('child_process');
const path = require('path');

const userProfile = process.env.USERPROFILE;
const adb = path.join(userProfile, 'AppData', 'Local', 'Android', 'Sdk', 'platform-tools', 'adb.exe');

console.log('=== adb devices ===');
try {
  console.log(execSync(`"${adb}" devices -l`, { encoding: 'utf8' }));
} catch (e) { console.error('失败:', e.message); }

console.log('=== emulator.exe 进程 ===');
try {
  console.log(execSync('tasklist /FI "IMAGENAME eq emulator.exe" /FO TABLE /NH', { encoding: 'utf8' }));
} catch (e) {}

console.log('=== qemu-system-x86_64-headless.exe 进程 ===');
try {
  console.log(execSync('tasklist /FI "IMAGENAME eq qemu-system-x86_64-headless.exe" /FO TABLE /NH', { encoding: 'utf8' }));
} catch (e) {}

console.log('=== boot_completed ===');
try {
  const out = execSync(`"${adb}" -s emulator-5554 shell getprop sys.boot_completed 2>&1`, { encoding: 'utf8' });
  console.log('boot_completed:', out.trim());
} catch (e) { console.log('失败:', e.message.slice(0, 200)); }

console.log('=== getprop ro.* ===');
try {
  const out = execSync(`"${adb}" -s emulator-5554 shell "getprop ro.build.version.release; getprop ro.build.version.sdk; getprop ro.product.model; getprop ro.product.cpu.abi" 2>&1`, { encoding: 'utf8' });
  console.log(out);
} catch (e) { console.log('失败:', e.message.slice(0, 200)); }
