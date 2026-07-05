// 重启 adb 并强制连接 5554
const { execSync } = require('child_process');
const path = require('path');

const userProfile = process.env.USERPROFILE;
const adb = path.join(userProfile, 'AppData', 'Local', 'Android', 'Sdk', 'platform-tools', 'adb.exe');

function run(cmd, opts = {}) {
  console.log(`\n$ ${cmd}`);
  try {
    const out = execSync(cmd, { encoding: 'utf8', stdio: 'pipe', ...opts });
    console.log(out || '(no output)');
    return out;
  } catch (e) {
    console.error('失败:', e.message);
    return null;
  }
}

run(`"${adb}" kill-server`);
run(`"${adb}" start-server`);
run(`"${adb}" connect localhost:5555`);  // QEMU 监听 5555 还是 5554 ?
run(`"${adb}" connect 127.0.0.1:5554`);
run(`"${adb}" connect 127.0.0.1:5555`);
run(`"${adb}" devices`);

console.log('\n=== 检查端口监听 ===');
run('netstat -an | Select-String "5554|5555|5556"');
