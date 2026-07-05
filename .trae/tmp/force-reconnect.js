// 强制 adb 连接 (重写 - 修复模块语法)
const { execSync } = require('child_process');
const path = require('path');

const userProfile = process.env.USERPROFILE;
const adb = path.join(userProfile, 'AppData', 'Local', 'Android', 'Sdk', 'platform-tools', 'adb.exe');

function run(cmd) {
  console.log(`\n$ ${cmd}`);
  try { return execSync(cmd, { encoding: 'utf8', stdio: 'pipe' }); }
  catch (e) { return `FAILED: ${e.message}`; }
}

async function main() {
  console.log('=== 当前 adb 状态 ===');
  console.log(run(`"${adb}" devices -l`));

  console.log('\n=== 检查 5554 5555 端口是否监听 ===');
  console.log(run('netstat -ano | findstr "5554 5555"'));

  console.log('\n=== 重启 adb 强制 reconnect ===');
  console.log(run(`"${adb}" kill-server`));
  console.log(run(`"${adb}" start-server`));

  for (let i = 0; i < 10; i++) {
    await new Promise(r => setTimeout(r, 2000));
    const devs = run(`"${adb}" devices -l`);
    console.log(`[${i * 2}s]`, devs);
    if (devs && !devs.includes('offline')) break;
  }

  console.log('\n=== wait-for-device + shell ===');
  console.log(run(`"${adb}" -s emulator-5554 wait-for-device 2>&1`));
  console.log(run(`"${adb}" -s emulator-5554 shell whoami 2>&1`));
}

main();
