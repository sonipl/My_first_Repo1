#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Installs permanent vCenter SSH tunnel on Windows.
.DESCRIPTION
  Copies scripts, configures SSH, optional hosts entry, and Task Scheduler auto-start.
#>
param(
    [switch]$SkipHosts,
    [switch]$SkipTask
)

$ErrorActionPreference = "Stop"
$InstallDir = "C:\Tools\vcenter-tunnel"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$SshConfig  = Join-Path $env:USERPROFILE ".ssh\config"
$HostsFile  = "$env:Windir\System32\drivers\etc\hosts"
$TaskName   = "vCenter SSH Tunnel"

Write-Host "==> vCenter SSH Tunnel Installer" -ForegroundColor Cyan

# 1. OpenSSH client
$SshExe = "C:\Windows\System32\OpenSSH\ssh.exe"
if (-not (Test-Path $SshExe)) {
    Write-Host "Installing OpenSSH Client..." -ForegroundColor Yellow
    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 | Out-Null
}
Write-Host "OK  OpenSSH client" -ForegroundColor Green

# 2. Install scripts
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item (Join-Path $ScriptRoot "start-tunnel.ps1") $InstallDir -Force
Copy-Item (Join-Path $ScriptRoot "start-tunnel.bat")  $InstallDir -Force
Write-Host "OK  Scripts -> $InstallDir" -ForegroundColor Green

# 3. SSH config
$SshDir = Split-Path $SshConfig -Parent
New-Item -ItemType Directory -Force -Path $SshDir | Out-Null
$Snippet = Get-Content (Join-Path $ScriptRoot "ssh-config-snippet") -Raw
$MarkerStart = "# >>> vcenter-tunnel >>>"
$MarkerEnd   = "# <<< vcenter-tunnel <<<"

if (Test-Path $SshConfig) {
    $Existing = Get-Content $SshConfig -Raw
} else {
    $Existing = ""
}

if ($Existing -match [regex]::Escape($MarkerStart)) {
    Write-Host "OK  SSH config already contains vcenter-tunnel block" -ForegroundColor Green
} else {
    $Block = @"

$MarkerStart
$Snippet
$MarkerEnd
"@
    Add-Content -Path $SshConfig -Value $Block -Encoding utf8
    Write-Host "OK  SSH config updated -> $SshConfig" -ForegroundColor Green
}

# 4. Hosts file (optional — fixes vCenter SSL cert when using https://vc01.vmalpha.com)
if (-not $SkipHosts) {
    $HostsEntry = "127.0.0.1   vc01.vmalpha.com"
    $HostsContent = Get-Content $HostsFile -ErrorAction SilentlyContinue
    if ($HostsContent -match "vc01\.vmalpha\.com") {
        Write-Host "OK  Hosts entry already present" -ForegroundColor Green
    } else {
        Add-Content -Path $HostsFile -Value "`n$HostsEntry" -Encoding ascii
        Write-Host "OK  Added hosts entry: $HostsEntry" -ForegroundColor Green
        Write-Host "    You can use https://vc01.vmalpha.com (still tunneled via port 8443 in browser if needed)" -ForegroundColor DarkGray
    }
}

# 5. Scheduled task
if (-not $SkipTask) {
    $Action = New-ScheduledTaskAction -Execute "C:\Tools\vcenter-tunnel\start-tunnel.bat"
    $Trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 365)
    $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Description "SSH tunnel to vc01.vmalpha.com via ac01 (192.168.68.26)" | Out-Null
    Write-Host "OK  Scheduled task registered: $TaskName (runs at login)" -ForegroundColor Green
}

Write-Host ""
Write-Host "==> Installation complete" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Set up SSH key (recommended): ssh-keygen -t ed25519"
Write-Host "     Copy pubkey to ac01: ~/.ssh/authorized_keys"
Write-Host "  2. Test tunnel now:"
Write-Host "       ssh -N vcenter-tunnel"
Write-Host "  3. Open vCenter:"
Write-Host "       https://localhost:8443"
Write-Host "  4. Or start scheduled task:"
Write-Host "       Start-ScheduledTask -TaskName '$TaskName'"
Write-Host ""
Write-Host "Log: C:\Tools\vcenter-tunnel\tunnel.log" -ForegroundColor DarkGray
