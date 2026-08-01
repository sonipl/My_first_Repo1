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

# Prefer FQDN-friendly forward on 443; fall back to 8443 if binding 443 fails.
$TunnelHost = "vcenter-tunnel"
while ($true) {
    Write-Log "Starting vCenter SSH tunnel ($TunnelHost -> vc01.vmalpha.com:443)..."
    & $SshExe -N $TunnelHost 2>&1 | ForEach-Object {
        Write-Log $_
        if ($_ -match 'Cannot assign requested address|Privilege separation user|bind|Address already in use|Permission denied') {
            if ($TunnelHost -eq "vcenter-tunnel") {
                Write-Log "WARN: LocalForward 443 failed; switching to vcenter-tunnel-8443"
                $TunnelHost = "vcenter-tunnel-8443"
            }
        }
    }
    Write-Log "Tunnel stopped. Reconnecting in 10 seconds..."
    Start-Sleep -Seconds 10
}
