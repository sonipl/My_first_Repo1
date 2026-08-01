#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Fix Firefox HTTPS errors for vc01.vmalpha.com (and related lab FQDNs).

.DESCRIPTION
  1. Updates Windows hosts with lab FQDN mappings
  2. Fetches the TLS certificate from vCenter and trusts it in Windows
  3. Makes Firefox trust Windows enterprise/root CAs
  4. Flushes DNS

.PARAMETER TunnelMode
  Map vc01.vmalpha.com to 127.0.0.1 (use with LocalForward 443 SSH tunnel).
  Default is direct LAN: 192.168.71.20.

.PARAMETER SkipHosts
  Do not modify the hosts file.

.PARAMETER SkipCert
  Do not import certificates.

.EXAMPLE
  # Direct LAN access (default)
  .\fix-firefox-https.ps1

.EXAMPLE
  # Access via local SSH tunnel on port 443
  .\fix-firefox-https.ps1 -TunnelMode
#>
param(
    [switch]$TunnelMode,
    [switch]$SkipHosts,
    [switch]$SkipCert,
    [string]$VcenterHost = "vc01.vmalpha.com",
    [int]$VcenterPort = 443
)

$ErrorActionPreference = "Stop"
$HostsFile = "$env:Windir\System32\drivers\etc\hosts"
$MarkerStart = "# >>> vmalpha-lab >>>"
$MarkerEnd   = "# <<< vmalpha-lab <<<"

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "OK  $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "!!  $msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "Firefox / Windows HTTPS fix for vc01.vmalpha.com" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# 1. Hosts file
# ---------------------------------------------------------------------------
if (-not $SkipHosts) {
    Write-Step "Updating hosts file"

    if ($TunnelMode) {
        $LabBlock = @"
$MarkerStart
127.0.0.1 vc01.vmalpha.com vc01
192.168.71.21 oelbm01.vmalpha.com oelbm01
192.168.71.22 foreman.vmalpha.com foreman
192.168.71.26 ac01.vmalpha.com ac01
$MarkerEnd
"@
        Write-Warn "TunnelMode: vc01 -> 127.0.0.1 (requires SSH LocalForward 443)"
    } else {
        $LabBlock = @"
$MarkerStart
192.168.71.20 vc01.vmalpha.com vc01
192.168.71.21 oelbm01.vmalpha.com oelbm01
192.168.71.22 foreman.vmalpha.com foreman
192.168.71.26 ac01.vmalpha.com ac01
$MarkerEnd
"@
    }

    $raw = ""
    if (Test-Path $HostsFile) {
        $raw = Get-Content $HostsFile -Raw -ErrorAction SilentlyContinue
        if ($null -eq $raw) { $raw = "" }
    }

    # Remove previous lab block and any loose vc01 / vmalpha lines we manage
    if ($raw -match [regex]::Escape($MarkerStart)) {
        $raw = [regex]::Replace(
            $raw,
            "(?s)" + [regex]::Escape($MarkerStart) + ".*?" + [regex]::Escape($MarkerEnd) + "\r?\n?",
            ""
        )
    }

    $lines = $raw -split "`r?`n"
    $kept = foreach ($line in $lines) {
        if ($line -match '(?i)\b(vc01\.vmalpha\.com|oelbm01\.vmalpha\.com|foreman\.vmalpha\.com|ac01\.vmalpha\.com)\b') {
            continue
        }
        # Drop old tunnel-only entry without FQDN list
        if ($line -match '^\s*127\.0\.0\.1\s+vc01\.vmalpha\.com\s*$') {
            continue
        }
        $line
    }
    $cleaned = ($kept -join "`r`n").TrimEnd() + "`r`n`r`n" + $LabBlock.TrimEnd() + "`r`n"

    Set-Content -Path $HostsFile -Value $cleaned -Encoding ascii -NoNewline:$false
    Write-Ok "Hosts updated ($HostsFile)"

    Write-Step "Flushing DNS cache"
    ipconfig /flushdns | Out-Null
    Write-Ok "DNS cache flushed"
} else {
    Write-Warn "Skipping hosts update (-SkipHosts)"
}

# ---------------------------------------------------------------------------
# 2. Resolve + connectivity check
# ---------------------------------------------------------------------------
Write-Step "Resolving $VcenterHost"
try {
    $resolved = [System.Net.Dns]::GetHostAddresses($VcenterHost) |
        Select-Object -ExpandProperty IPAddressToString
    Write-Ok ("Resolves to: " + ($resolved -join ", "))
} catch {
    Write-Warn "Could not resolve $VcenterHost — check hosts file / DNS"
}

$targetIp = if ($TunnelMode) { "127.0.0.1" } else { "192.168.71.20" }
Write-Step "Testing TCP ${targetIp}:$VcenterPort"
try {
    $tcpTest = Test-NetConnection -ComputerName $targetIp -Port $VcenterPort -WarningAction SilentlyContinue
    if ($tcpTest.TcpTestSucceeded) {
        Write-Ok "Port $VcenterPort is open on $targetIp"
    } else {
        Write-Warn "Port $VcenterPort is NOT reachable on $targetIp"
        if ($TunnelMode) {
            Write-Warn "Start the tunnel first: Start-ScheduledTask -TaskName 'vCenter SSH Tunnel'"
            Write-Warn "Or: ssh -N vcenter-tunnel  (with LocalForward 443)"
        } else {
            Write-Warn "Confirm VPN / lab network access to 192.168.71.20"
        }
    }
} catch {
    Write-Warn "Connectivity test failed: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# 3. Fetch TLS cert(s) and trust in Windows
# ---------------------------------------------------------------------------
if (-not $SkipCert) {
    Write-Step "Fetching TLS certificate from ${VcenterHost}:$VcenterPort"

    $certsToImport = @()
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.ReceiveTimeout = 15000
        $tcp.SendTimeout = 15000
        $tcp.Connect($VcenterHost, $VcenterPort)

        $callback = [System.Net.Security.RemoteCertificateValidationCallback] { $true }
        $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, $callback)
        # ServerName for SNI / hostname check bypass via callback
        $ssl.AuthenticateAsClient($VcenterHost)

        $remote = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($ssl.RemoteCertificate)
        $certsToImport += $remote
        Write-Ok ("Leaf cert: CN=" + $remote.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false))
        Write-Host ("    Issuer : " + $remote.Issuer) -ForegroundColor DarkGray
        Write-Host ("    Expires: " + $remote.NotAfter) -ForegroundColor DarkGray
        Write-Host ("    Thumb  : " + $remote.Thumbprint) -ForegroundColor DarkGray

        # Include chain intermediates / root when available
        $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
        $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
        [void]$chain.Build($remote)
        foreach ($el in $chain.ChainElements) {
            $c = $el.Certificate
            if ($certsToImport.Thumbprint -notcontains $c.Thumbprint) {
                $certsToImport += $c
                Write-Ok ("Chain cert: " + $c.Subject)
            }
        }

        $ssl.Close()
        $tcp.Close()
    } catch {
        Write-Warn "Could not fetch certificate: $($_.Exception.Message)"
        Write-Warn "If using a tunnel, ensure LocalForward 443 is up, then re-run."
        $certsToImport = @()
    }

    if ($certsToImport.Count -gt 0) {
        Write-Step "Importing certificate(s) into LocalMachine Trusted Root"
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
            [System.Security.Cryptography.X509Certificates.StoreName]::Root,
            [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
        )
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        foreach ($c in $certsToImport) {
            $exists = $store.Certificates | Where-Object { $_.Thumbprint -eq $c.Thumbprint }
            if ($exists) {
                Write-Ok "Already trusted: $($c.Thumbprint)"
            } else {
                $store.Add($c)
                Write-Ok "Imported: $($c.Subject)"
            }
        }
        $store.Close()
    }
} else {
    Write-Warn "Skipping certificate import (-SkipCert)"
}

# ---------------------------------------------------------------------------
# 4. Make Firefox trust Windows root CAs
# ---------------------------------------------------------------------------
Write-Step "Configuring Firefox to trust Windows enterprise / root CAs"

$policyRoots = @(
    "${env:ProgramFiles}\Mozilla Firefox\distribution",
    "${env:ProgramFiles(x86)}\Mozilla Firefox\distribution"
)

$policyJson = @'
{
  "policies": {
    "Certificates": {
      "ImportEnterpriseRoots": true
    }
  }
}
'@

$policyWritten = $false
foreach ($dir in $policyRoots) {
    $firefoxExe = Join-Path (Split-Path $dir -Parent) "firefox.exe"
    if (-not (Test-Path $firefoxExe)) { continue }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $policyPath = Join-Path $dir "policies.json"
    if (Test-Path $policyPath) {
        try {
            $existing = Get-Content $policyPath -Raw | ConvertFrom-Json
            if (-not $existing.policies) {
                $existing | Add-Member -NotePropertyName policies -NotePropertyValue (@{}) -Force
            }
            if (-not $existing.policies.Certificates) {
                $existing.policies | Add-Member -NotePropertyName Certificates -NotePropertyValue (@{}) -Force
            }
            $existing.policies.Certificates | Add-Member -NotePropertyName ImportEnterpriseRoots -NotePropertyValue $true -Force
            $existing | ConvertTo-Json -Depth 8 | Set-Content -Path $policyPath -Encoding utf8
            Write-Ok "Updated Firefox policy: $policyPath"
            $policyWritten = $true
        } catch {
            Set-Content -Path $policyPath -Value $policyJson -Encoding utf8
            Write-Ok "Replaced Firefox policy: $policyPath"
            $policyWritten = $true
        }
    } else {
        Set-Content -Path $policyPath -Value $policyJson -Encoding utf8
        Write-Ok "Wrote Firefox policy: $policyPath"
        $policyWritten = $true
    }
}

# Also set user.js pref in all profiles (covers portable / older installs)
$profilesRoot = Join-Path $env:APPDATA "Mozilla\Firefox\Profiles"
if (Test-Path $profilesRoot) {
    Get-ChildItem $profilesRoot -Directory | ForEach-Object {
        $userJs = Join-Path $_.FullName "user.js"
        $prefLine = 'user_pref("security.enterprise_roots.enabled", true);'
        if (Test-Path $userJs) {
            $content = Get-Content $userJs -Raw
            if ($content -notmatch 'security\.enterprise_roots\.enabled') {
                Add-Content -Path $userJs -Value "`n$prefLine"
                Write-Ok "Enabled enterprise_roots in $($_.Name)\user.js"
            } else {
                $content = $content -replace 'user_pref\("security\.enterprise_roots\.enabled",\s*(true|false)\);', $prefLine
                Set-Content -Path $userJs -Value $content -Encoding utf8
                Write-Ok "Updated enterprise_roots in $($_.Name)\user.js"
            }
        } else {
            Set-Content -Path $userJs -Value $prefLine -Encoding utf8
            Write-Ok "Created $($_.Name)\user.js with enterprise_roots"
        }
    }
} else {
    Write-Warn "No Firefox profiles found under $profilesRoot (open Firefox once, then re-run)"
}

if (-not $policyWritten) {
    Write-Warn "Firefox install not found under Program Files — profile user.js still applied if present"
}

# ---------------------------------------------------------------------------
# 5. Done
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Done" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Fully quit Firefox (check system tray) and reopen it"
Write-Host "  2. Open:  https://$VcenterHost/"
if ($TunnelMode) {
    Write-Host "  3. Ensure tunnel is running with LocalForward 443 (see README)"
} else {
    Write-Host "  3. If it still fails, try:  https://${targetIp}/  and compare the cert name"
}
Write-Host ""
Write-Host "If Firefox still warns, click Advanced → View Certificate and note the error code." -ForegroundColor DarkGray
Write-Host "Common: SEC_ERROR_UNKNOWN_ISSUER (re-run after vCenter is reachable) or SSL_ERROR_BAD_CERT_DOMAIN (cert name mismatch)." -ForegroundColor DarkGray
Write-Host ""
