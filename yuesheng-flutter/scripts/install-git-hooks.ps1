#Requires -Version 5
# ============================================================================
# 月笙写作教练 —— 本地 pre-commit hook 一键安装脚本
#
# 功能：
#   1. 把 yuesheng-flutter/scripts/git-hooks/pre-commit 复制到 .git/hooks/pre-commit
#   2. 已存在旧 pre-commit 时先备份为 pre-commit.bak.<unix-time-ms>
#   3. 检查 core.hooksPath 是否会把 .git/hooks/ 顶掉（设了就报警告）
#
# ★ 2026-09-17 修两处坏点（此前本脚本**必然抛异常、从未成功执行过**）：
#   a) `Join-Path $ScriptDir 'git-hookspre-commit'` —— 缺目录分隔符，
#      源路径拼成了 `<scripts>\git-hookspre-commit`，`Test-Path` 必然为假
#      ⇒ throw「Hook 源文件不存在」。
#   b) 旧版把 hook 写进 `<repo>/.githooks/pre-commit`，但**从不设置
#      core.hooksPath** —— 该目录不是 git 的默认 hook 位置，即便装上也不生效。
#      现改为写入 git 的默认生效路径 `<git-dir>/hooks/pre-commit`（零配置）。
#   c) （2026-09-17 安装前复核追加）目标目录原用**字面量 `.git`** 拼接，违反
#      AGENTS.md §9 硬纪律（`.git/` 路径必须走 `git rev-parse`）；改用
#      `--absolute-git-dir`。
#
# 用法（在仓库任意子目录执行）：
#   pwsh yuesheng-flutter/scripts/install-git-hooks.ps1
#
# 卸载：
#   Remove-Item .git/hooks/pre-commit
#
# 跳过快道的紧急提交方式：
#   $env:SKIP_GIT_GATE=1 ; git commit ...        # PowerShell
#   SKIP_GIT_GATE=1 git commit ...                 # Git Bash / WSL / macOS / Linux
# ============================================================================
$ErrorActionPreference = 'Stop'

# 定位仓库根（基于 install 脚本所在路径向上找 .git，或直接 git rev-parse）
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $ScriptDir
try {
    $RepoRoot = & git rev-parse --show-toplevel 2>$null
    if (-not $RepoRoot) {
        throw '无法定位 git 仓库根，请在仓库目录内执行本脚本。'
    }
    Write-Host "[install-git-hooks] 仓库根：$RepoRoot"

    # ---- 源 hook（★ 修点 a：显式分两段拼路径）----
    $SrcHook = Join-Path (Join-Path $ScriptDir 'git-hooks') 'pre-commit'
    if (-not (Test-Path $SrcHook)) {
        throw "Hook 源文件不存在：$SrcHook"
    }

    # ---- 目标：git 的默认生效路径 <git-dir>/hooks/（★ 修点 b）----
    # ★ 修点 c（2026-09-17 安装前复核）：旧写法用**字面量 `.git`**，违反项目硬纪律
    #   「任何 `.git/` 路径操作都要用 `git rev-parse --git-dir`，不要写字面量 `.git`」
    #   （AGENTS.md §9；2026-09-06 实证：在子目录里建出**假 `.git`**，ref 全不生效）。
    #   改用 `--absolute-git-dir`：对 cwd 在子目录 / worktree / 子模块等情形均正确。
    $GitDir = & git rev-parse --absolute-git-dir 2>$null
    if (-not $GitDir) {
        throw '无法定位 git 目录（git rev-parse --absolute-git-dir 失败）。'
    }
    $HooksDir = Join-Path $GitDir 'hooks'
    if (-not (Test-Path $HooksDir)) {
        New-Item -ItemType Directory -Path $HooksDir -Force | Out-Null
    }

    # ---- 前置警告：core.hooksPath 会把 .git/hooks/ 整个顶掉 ----
    $HooksPath = & git config --get core.hooksPath 2>$null
    if ($HooksPath) {
        Write-Warning ("core.hooksPath 已设为 '{0}' —— git 将忽略 .git/hooks/，" -f $HooksPath)
        Write-Warning "本脚本装入的 hook 不会生效。请先执行：git config --unset core.hooksPath"
    }

    $DstHook = Join-Path $HooksDir 'pre-commit'
    if (Test-Path $DstHook) {
        $Bak = $DstHook + '.bak.' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        Copy-Item -Path $DstHook -Destination $Bak
        Write-Host "[install-git-hooks] 旧 hook 已备份：$Bak"
    }

    Copy-Item -Path $SrcHook -Destination $DstHook -Force
    Write-Host "[install-git-hooks] ✅ 已将 pre-commit 安装到：$DstHook"
    Write-Host ""
    Write-Host "行为：仅当改动触及 yuesheng-flutter/ 或 flutter_ci.yaml 时运行**快道**"
    Write-Host "      （scripts/gate-fast.sh，约 40 秒）。快道不含门禁 6（覆盖率）。"
    Write-Host "      收尾请手工跑：cd yuesheng-flutter; bash scripts/gate.sh（十二道全量）"
    Write-Host ""
    Write-Host "👉 跳过快道（紧急提交）："
    Write-Host "   PowerShell：`$env:SKIP_GIT_GATE=1 ; git commit -m '...'"
    Write-Host "   Git Bash ：SKIP_GIT_GATE=1 git commit -m '...'"
} finally {
    Pop-Location
}
