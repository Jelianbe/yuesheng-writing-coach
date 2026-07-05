// boot 监控
const { execSync } = require('child_process');
const path = require('path');

const userProfile = process.env.USERPROFILE;
const adb = path.join(userProfile, 'AppData', 'Local', 'Android', 'Sdk', 'platform-tools', 'adb.exe');

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function main() {
  console.log('=== boot_completed 监控 (TCG 模式会很慢) ===');
  for (let i = 0; i < 200; i++) {
    await sleep(10000);  // 10s 间隔,最长 33 分钟
    try {
      // 重启 adb (以防连接丢失)
      const devs = execSync(`"${adb}" devices -l`, { encoding: 'utf8' });
      const lines = devs.split('\n').filter(l => l.includes('emulator') || l.includes('5554'));
      console.log(`[${(i + 1) * 10}s]`, lines.join(' | ') || '(no device)');

      if (lines.some(l => l.includes('device') && !l.includes('offline'))) {
        const out = execSync(`"${adb}" -s emulator-5554 shell getprop sys.boot_completed 2>&1`, { encoding: 'utf8' });
        const status = out.trim();
        console.log(`  boot_completed = "${status}"`);
        if (status === '1') {
          console.log('  -> [OK] 启动完成');
          return true;
        }
      }
    } catch (e) {
      // 设备未就绪
    }
  }
  return false;
}

main().then(ok => {
  if (ok) {
    try {
      const info = execSync(`"${adb}" -s emulator-5554 shell "echo 'Android: '$(getprop ro.build.version.release); echo 'SDK: '$(getprop ro.build.version.sdk); echo 'Model: '$(getprop ro.product.model)"`, { encoding: 'utf8' });
      console.log('\n' + info);
    } catch (e) {}
  } else {
    console.error('\n[FAIL] 启动超时');
  }
});
