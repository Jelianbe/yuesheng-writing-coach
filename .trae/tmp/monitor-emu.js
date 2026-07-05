// Monitor emulator boot + auto-install on device
// Uses Node.js (no PowerShell encoding issues)
const { execFile } = require('child_process');
const os = require('os');
const path = require('path');
const fs = require('fs');

const ADB = path.join(os.homedir(), 'AppData', 'Local', 'Android', 'Sdk', 'platform-tools', 'adb.exe');
const APK = 'D:\\ai-teacher\\yuesheng-writing-coach\\android\\app\\build\\outputs\\apk\\debug\\app-debug.apk';
const TICK_MS = 15000;
const MAX_WAIT_MS = 900000;
const start = Date.now();

function adb(...args) {
  return new Promise((resolve) => {
    execFile(ADB, args, { encoding: 'utf8', timeout: 12000, windowsHide: true }, (err, stdout, stderr) => {
      resolve({ code: err ? (err.code || -1) : 0, stdout: stdout || '', stderr: stderr || '' });
    });
  });
}

function qemuCpu() {
  try {
    const out = require('child_process').execSync(
      'powershell -NoProfile -Command "Get-Process -Name qemu-system-x86_64 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty CPU"',
      { encoding: 'utf8', timeout: 5000, windowsHide: true }
    );
    return out.trim() ? parseFloat(out.trim()) : null;
  } catch { return null; }
}

let installed = false;
let lastInstallTry = 0;

async function tick(tSec, tryInstall) {
  const cpu = qemuCpu();
  const dev = await adb('devices');
  const devLine = (dev.stdout.split(/\r?\n/).find(l => /emulator-\d/.test(l)) || '').trim();

  let boot = '';
  if (devLine.endsWith('device')) {
    const b = await adb('-s', 'emulator-5554', 'shell', 'getprop', 'sys.boot_completed');
    boot = (b.stdout || '').trim();
  }

  const cpuStr = cpu != null ? cpu.toFixed(1).padStart(7) + 's' : '   (none)';
  console.log(`[${String(tSec).padStart(4)}s] qemu_cpu=${cpuStr} | ${devLine || 'adb: (none)'} | boot=${boot}`);

  if (tryInstall && !installed && devLine.endsWith('device') && Date.now() - lastInstallTry > 30000) {
    lastInstallTry = Date.now();
    console.log('  >> device seen -- attempting install...');
    const inst = await adb('-s', 'emulator-5554', 'install', '-r', APK);
    const out = (inst.stdout + inst.stderr).trim();
    console.log('  >> install: ' + out.split(/\r?\n/)[0]);
    if (/Success/i.test(out)) {
      console.log('INSTALL OK');
      installed = true;
    } else {
      console.log('  >> install failed (will retry next tick)');
    }
  }
}

(async () => {
  if (!fs.existsSync(ADB)) { console.log('FATAL: adb not found at ' + ADB); process.exit(2); }
  if (!fs.existsSync(APK)) { console.log('FATAL: apk not found at ' + APK); process.exit(2); }
  console.log('adb: ' + ADB);
  console.log('apk: ' + APK);

  await tick(0, false);
  while (Date.now() - start < MAX_WAIT_MS) {
    await new Promise(r => setTimeout(r, TICK_MS));
    const t = Math.floor((Date.now() - start) / 1000);
    await tick(t, true);
    if (installed) { console.log('READY: app installed'); process.exit(0); }
  }
  console.log('TIMEOUT after ' + (MAX_WAIT_MS / 1000) + 's');
  process.exit(1);
})();
