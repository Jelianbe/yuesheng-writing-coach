$ErrorActionPreference = 'Continue'
# 关键: 不用字符串拼接中文路径,改用 .NET Process API (绕过 PowerShell ANSI 解析)
$adbPath = [System.IO.Path]::Combine($env:USERPROFILE, 'AppData\Local\Android\Sdk\platform-tools\adb.exe')
$apkPath = 'D:\ai-teacher\yuesheng-writing-coach\android\app\build\outputs\apk\debug\app-debug.apk'
$start = Get-Date
$maxWait = 900
$installed = $false

# 用 .NET 调 adb (UTF-8 输出,不走 PowerShell 解析)
function Invoke-Adb {
  param([string[]]$Arguments)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $adbPath
  foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
  $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
  $proc = [System.Diagnostics.Process]::Start($psi)
  $out = $proc.StandardOutput.ReadToEndAsync()
  $err = $proc.StandardError.ReadToEndAsync()
  $proc.WaitForExit(10000) | Out-Null
  return @{ ExitCode = $proc.ExitCode; StdOut = $out.Result; StdErr = $err.Result }
}

function Get-Snapshot {
  param([int]$t, [bool]$tryInstall)
  $line = "[{0,4}s]" -f $t
  $q = Get-Process -Name 'qemu-system-x86_64' -ErrorAction SilentlyContinue
  if ($q) { $line += " qemu_cpu={0,7:F1}s" -f $q.CPU } else { $line += " qemu_cpu=   (none)" }

  $dev = Invoke-Adb @('devices')
  $devList = ($dev.StdOut -split "`n" | Where-Object { $_ -match 'emulator-\d' }) -join ' | '
  if ($devList) { $line += " | " + $devList.Trim() } else { $line += " | adb: (none)" }

  if ($devList -match 'device\b') {
    $boot = Invoke-Adb @('-s', 'emulator-5554', 'shell', 'getprop', 'sys.boot_completed')
    if ($boot.StdOut) { $line += " boot=" + $boot.StdOut.Trim() }
  }

  Write-Host $line

  if ($tryInstall -and -not $installed -and $devList -match 'device\b') {
    Write-Host "  >> device seen -- attempting install..."
    $inst = Invoke-Adb @('-s', 'emulator-5554', 'install', '-r', $apkPath)
    $combined = $inst.StdOut + $inst.Stderr
    Write-Host "  >> install: $combined"
    if ($combined -match 'Success') {
      Write-Host "INSTALL OK"
      $installed = $true
    } else {
      Write-Host "  >> install failed (will retry next tick)"
    }
  }
}

# 启动时验证 adb 路径
if (-not (Test-Path $adbPath)) {
  Write-Host "FATAL: adb not found at $adbPath"
  exit 2
}
Write-Host "adb: $adbPath"
Write-Host "apk: $apkPath"

Get-Snapshot 0 $false
while (((Get-Date) - $start).TotalSeconds -lt $maxWait) {
  Start-Sleep -Seconds 15
  $t = [int]((Get-Date) - $start).TotalSeconds
  Get-Snapshot $t $true
  if ($installed) { Write-Host "READY: app installed"; exit 0 }
}
Write-Host "TIMEOUT after $maxWait seconds"
exit 1
