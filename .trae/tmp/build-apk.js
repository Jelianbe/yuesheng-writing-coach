// 构建 Capacitor Android Debug APK
const { spawn, execSync } = require('child_process');
const path = require('path');

const projectDir = 'd:\\ai-teacher\\yuesheng-writing-coach';
const androidDir = path.join(projectDir, 'android');
const gradle = path.join(androidDir, 'gradlew.bat');

const env = {
  ...process.env,
  ANDROID_HOME: 'C:\\Users\\月笙如歌\\AppData\\Local\\Android\\Sdk',
  ANDROID_SDK_ROOT: 'C:\\Users\\月笙如歌\\AppData\\Local\\Android\\Sdk',
  JAVA_HOME: 'C:\\Program Files\\Android\\Android Studio\\jbr',
};

console.log('=== 构建 Debug APK ===');
console.log('Gradle 路径:', gradle);
console.log('JAVA_HOME:', env.JAVA_HOME);
console.log('ANDROID_HOME:', env.ANDROID_HOME);

const proc = spawn(gradle, ['assembleDebug', '--no-daemon', '--console=plain'], {
  cwd: androidDir,
  env,
  stdio: 'inherit',
  shell: true,
  windowsHide: true,
});

proc.on('close', (code) => {
  console.log(`\n=== Gradle 退出码: ${code} ===`);
  if (code === 0) {
    const apk = path.join(androidDir, 'app', 'build', 'outputs', 'apk', 'debug', 'app-debug.apk');
    console.log('APK 路径:', apk);
    try {
      const stat = require('fs').statSync(apk);
      console.log('APK 大小:', (stat.size / 1024 / 1024).toFixed(2), 'MB');
    } catch (e) {
      console.log('APK 文件未找到');
    }
  } else {
    console.error('构建失败');
  }
});

proc.on('error', (e) => console.error('spawn error:', e));
