// 创建 AVD 脚本
const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const ANDROID_HOME = 'C:\\Users\\月笙如歌\\AppData\\Local\\Android\\Sdk';
const JAVA_HOME = 'C:\\Program Files\\Android\\Android Studio\\jbr';
const avdManager = path.join(ANDROID_HOME, 'cmdline-tools', 'latest', 'bin', 'avdmanager.bat');
const env = {
  ...process.env,
  ANDROID_HOME,
  ANDROID_SDK_ROOT: ANDROID_HOME,
  JAVA_HOME,
  PATH: `${JAVA_HOME}\\bin;${ANDROID_HOME}\\platform-tools;${ANDROID_HOME}\\emulator;${ANDROID_HOME}\\cmdline-tools\\latest\\bin;${process.env.PATH}`,
};

function run(cmd, opts = {}) {
  console.log(`\n$ ${cmd}`);
  try {
    const out = execSync(cmd, { env, stdio: 'inherit', shell: 'cmd.exe', ...opts });
    return out;
  } catch (e) {
    console.error('命令失败:', e.message);
    return null;
  }
}

console.log('=== Step 1: 创建 AVD ===');
// avdmanager 需要输入"no"以使用默认硬件配置,Windows 下需 echo | set
run(`echo no | "${avdManager}" create avd -n Pixel6 -k "system-images;android-34;google_apis;x86_64" -d "pixel_6" --force`);

console.log('\n=== Step 2: 列出 AVD ===');
run(`"${avdManager}" list avd`);
