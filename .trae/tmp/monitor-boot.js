// 持续监控 boot 完成
const { execSync } = require('child_process');
const path = require('path');

const userProfile = process.env.USERPROFILE;
const adb = path.join(userProfile, 'AppData', 'Local', 'Android', 'Sdk', 'platform-tools', 'adb.exe');

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function main() {
  console.log('=== 持续监控 boot_completed ===');
  for (let i = 0; i < 100; i++) {
    await sleep(5000);
    try {
      const out = execSync(`"${adb}" -s emulator-5554 shell getprop sys.boot_completed 2>&1`, { encoding: 'utf8' });
      const status = out.trim();
      console.log(`[${(i + 1) * 5}s] boot_completed = "${status}"`);
      if (status === '1') {
        console.log('  -> [OK] 启动完成');
        return true;
      }
    } catch (e) {
      // shell 还没就绪
    }
    // 每 30s 输出 devices 状态
    if ((i + 1) % 6 === 0) {
      try {
        const out = execSync(`"${adb}" devices -l`, { encoding: 'utf8' });
        const filtered = out.split('\n').filter(l => l.includes('5554') || l.includes('5555') || l.includes('emulator'));
        if (filtered.length) {
          console.log('  设备状态:', filtered.join(' | '));
        }
      } catch (e) {}
    }
  }
  return false;
}

main().then(ok => {
  if (ok) {
    console.log('\n=== 设备信息 ===');
    try {
      const info = execSync(`"${adb}" -s emulator-5554 shell "echo Android: $(getprop ro.build.version.release); echo SDK: $(getprop ro.build.version.sdk); echo Model: $(getprop ro.product.model); echo ABI: $(getprop ro.product.cpu.abi)"`, { encoding: 'utf8' });
      console.log(info);
    } catch (e) {}
  } else {
    console.error('\n[FAIL] 启动超时 (8+ 分钟)');
  }
});
