$LogFile = "C:\Tools\vcenter-tunnel\tunnel.log"
$SshExe  = "C:\Windows\System32\OpenSSH\ssh.exe"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts $msg" | Out-File -FilePath $LogFile -Append -Encoding utf8
}

if (-not (Test-Path $SshExe)) {
    Write-Log "ERROR: OpenSSH not found at $SshExe. Install OpenSSH Client via Windows Optional Features."
    exit 1
}

while ($true) {
    Write-Log "Starting vCenter SSH tunnel (vcenter-tunnel -> vc01.vmalpha.com:443 on localhost:8443)..."
    & $SshExe -N vcenter-tunnel 2>&1 | ForEach-Object { Write-Log $_ }
    Write-Log "Tunnel stopped. Reconnecting in 10 seconds..."
    Start-Sleep -Seconds 10
}
