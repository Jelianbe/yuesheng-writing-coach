// 深度诊断
const { execSync } = require('child_process');
const path = require('path');

const userProfile = process.env.USERPROFILE;
const adb = path.join(userProfile, 'AppData', 'Local', 'Android', 'Sdk', 'platform-tools', 'adb.exe');

function run(cmd) {
  console.log(`\n$ ${cmd}`);
  try {
    const out = execSync(cmd, { encoding: 'utf8', stdio: 'pipe' });
    return out;
  } catch (e) {
    return 'FAILED: ' + e.message;
  }
}

console.log('=== 进程资源 ===');
console.log(run('tasklist /FI "IMAGENAME eq qemu-system-x86_64-headless.exe" /FO TABLE /NH'));
console.log(run('tasklist /FI "IMAGENAME eq emulator.exe" /FO TABLE /NH'));
console.log(run('wmic process where "name=\'qemu-system-x86_64-headless.exe\'" get processid,workingsetsize,kernelmodetime,usermodetime /format:list 2>nul'));

console.log('\n=== 端口监听 ===');
console.log(run('netstat -ano | findstr "5554 5555"'));

console.log('\n=== 设备状态 ===');
console.log(run(`"${adb}" devices -l`));

console.log('\n=== 尝试不同的连接方式 ===');
console.log(run(`"${adb}" disconnect`));
console.log(run(`"${adb}" connect emulator-5554`));
console.log(run(`"${adb}" connect 127.0.0.1:5554`));
console.log(run(`"${adb}" devices`));
