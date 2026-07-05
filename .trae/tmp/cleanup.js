// 清理所有 emulator/qemu 进程
const { execSync } = require('child_process');
const path = require('path');

const userProfile = process.env.USERPROFILE;
const adb = path.join(userProfile, 'AppData', 'Local', 'Android', 'Sdk', 'platform-tools', 'adb.exe');

function run(cmd) {
  console.log(`$ ${cmd}`);
  try { return execSync(cmd, { encoding: 'utf8', stdio: 'inherit' }); }
  catch (e) { return null; }
}

console.log('=== 杀掉所有 ===');
run('taskkill /F /IM emulator.exe /T');
run('taskkill /F /IM qemu-system-x86_64-headless.exe /T');
run('taskkill /F /IM qemu-system-x86_64.exe /T');
run(`"${adb}" kill-server`);

console.log('\n=== 验证 ===');
run('tasklist /FI "IMAGENAME eq emulator.exe"');
run('tasklist /FI "IMAGENAME eq qemu-system-x86_64-headless.exe"');
run('netstat -ano | findstr "5554 5555"');
