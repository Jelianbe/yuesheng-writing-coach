## 启动 AVD 模拟器步骤

### 方法 1(最快,推荐)
1. 打开 Android Studio(桌面图标或开始菜单)
2. 顶部菜单:Tools → Device Manager(或 More Actions → Virtual Device Manager)
3. 看到已有 AVD(之前"Standard 安装"应该自动创建了一个 Pixel / API 34)
4. 点击 ▶ 绿色三角启动
5. 等待模拟器开机(2-3 分钟,首次更慢)
6. 看到主屏幕就绪后告诉我

### 方法 2(命令行)
1. 找到 emulator.exe:
   - 已加 PATH: `emulator -list-avds` 列出所有 AVD
   - 或 `& "$env:ANDROID_HOME\emulator\emulator.exe" -list-avds`
2. 启动: `emulator -avd <AVD名称>` 或 `& "$env:ANDROID_HOME\emulator\emulator.exe" -avd <AVD名称>`

如果 AVD 列表为空,需要先在 Android Studio 创建(Standard 安装通常会创建一个 Pixel API 34)

### 验证
adb devices  # 应该看到 emulator-5554 device

### 准备就绪后告诉我
我会在 APK 编译完成后,adb install + 启动应用,看 sessions 页面是否正常加载
