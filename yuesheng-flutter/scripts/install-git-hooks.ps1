#Requires -Version 5
# ============================================================================
# 月笙写作教练 —— 本地 pre-commit hook 一键安装脚本
#
# 功能：
#   1. 把 yuesheng-flutter/scripts/git-hooks/pre-commit 复制到 .git/hooks/pre-commit
#   2. 已存在旧 pre-commit 时先备份为 pre-commit.bak.<unix-time-ms>
#
# 用法（在仓库根执行）：
#   pwsh yuesheng-flutter/scripts/install-git-hooks.ps1
#
# 跳过四闸的紧急提交方式：
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

    $SrcHook = Join-Path $ScriptDir 'git-hookspre-commit'
    if (-not (Test-Path $SrcHook)) {
        throw "Hook 源文件不存在：$SrcHook"
    }

    $HooksDir = Join-Path $RepoRoot '.githooks'
    if (-not (Test-Path $HooksDir)) {
        New-Item -ItemType Directory -Path $HooksDir -Force | Out-Null
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
    Write-Host "👉 跳过四闸（紧急提交）："
    Write-Host "   PowerShell：`$env:SKIP_GIT_GATE=1 ; git commit -m '...'"
    Write-Host "   Git Bash ：SKIP_GIT_GATE=1 git commit -m '...'"
} finally {
    Pop-Location
}
