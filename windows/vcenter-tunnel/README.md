# vCenter access from Windows (hosts + Firefox HTTPS + optional SSH tunnel)

Reach **https://vc01.vmalpha.com/** from your Windows laptop.

## Quick fix: Firefox HTTPS error (recommended)

If Firefox shows a certificate / secure connection error for `https://vc01.vmalpha.com/`, run this **as Administrator** in PowerShell:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
cd C:\path\to\My_first_Repo1\windows\vcenter-tunnel

# Direct lab / VPN access (192.168.71.20)
.\fix-firefox-https.ps1
```

What it does:

1. Writes lab FQDN entries to `C:\Windows\System32\drivers\etc\hosts`
2. Fetches the vCenter TLS certificate and imports it into **Windows Trusted Root**
3. Configures Firefox to trust Windows enterprise/root CAs (`ImportEnterpriseRoots`)
4. Flushes DNS

Then **fully quit Firefox** (including tray) and open:

```text
https://vc01.vmalpha.com/
```

### Hosts entries (direct LAN — default)

```text
192.168.71.20 vc01.vmalpha.com vc01
192.168.71.21 oelbm01.vmalpha.com oelbm01
192.168.71.22 foreman.vmalpha.com foreman
192.168.71.26 ac01.vmalpha.com ac01
```

### Tunnel mode (when you cannot reach 192.168.71.20 directly)

```powershell
# Map vc01 -> 127.0.0.1 and use SSH LocalForward 443
.\fix-firefox-https.ps1 -TunnelMode
```

Requires the SSH tunnel below with `LocalForward 443`.

---

## Optional: permanent SSH tunnel via ac01

```text
Browser → vc01.vmalpha.com:443 → SSH LocalForward → ac01 → vc01:443
```

### One-command install (PowerShell as Administrator)

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
cd C:\path\to\My_first_Repo1\windows\vcenter-tunnel
.\install.ps1
```

The installer will:

1. Copy tunnel scripts to `C:\Tools\vcenter-tunnel\`
2. Append SSH config to `%USERPROFILE%\.ssh\config`
3. Update hosts + Firefox trust prefs (TunnelMode)
4. Create a Task Scheduler job to start the tunnel at login

After the tunnel is up:

```powershell
cd C:\Tools\vcenter-tunnel
.\fix-firefox-https.ps1 -TunnelMode
```

### Manual tunnel test

```powershell
ssh -N vcenter-tunnel          # https://vc01.vmalpha.com/  (port 443)
# or
ssh -N vcenter-tunnel-8443     # https://localhost:8443
```

---

## After install

| What | Value |
|------|-------|
| Direct URL | https://vc01.vmalpha.com/ |
| Tunnel fallback | https://localhost:8443 |
| Jump host | psoni@192.168.71.26 (ac01) |
| Log file | C:\Tools\vcenter-tunnel\tunnel.log |
| Stop tunnel | Task Scheduler → disable/end `vCenter SSH Tunnel` |
| Start manually | `C:\Tools\vcenter-tunnel\start-tunnel.bat` |

## SSH key (recommended)

```powershell
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_ed25519 -N '""'
type $env:USERPROFILE\.ssh\id_ed25519.pub
```

On ac01:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "PASTE_PUBLIC_KEY" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

## Troubleshooting

```powershell
# Resolve + ping
ping vc01.vmalpha.com
nslookup vc01.vmalpha.com

# Is anything listening on 443 / 8443?
netstat -an | findstr ":443 :8443"

# View tunnel log
Get-Content C:\Tools\vcenter-tunnel\tunnel.log -Tail 30

# Test SSH to jump host
ssh ac01

# Re-run cert trust after vCenter is reachable
.\fix-firefox-https.ps1
```

| Firefox error | Fix |
|---------------|-----|
| `SEC_ERROR_UNKNOWN_ISSUER` / self-signed | Re-run `fix-firefox-https.ps1`, restart Firefox |
| `SSL_ERROR_BAD_CERT_DOMAIN` | Cert name mismatch — use the CN/SAN on the cert, or regenerate vCenter cert |
| `PR_END_OF_FILE_ERROR` / connection reset | Tunnel/port wrong — start tunnel or check `192.168.71.20:443` |
| Page never loads | Hosts point to wrong IP, or tunnel not running |

## Uninstall

```powershell
Unregister-ScheduledTask -TaskName "vCenter SSH Tunnel" -Confirm:$false
Remove-Item -Recurse -Force C:\Tools\vcenter-tunnel
# Remove vcenter-tunnel / ac01 blocks from %USERPROFILE%\.ssh\config
# Remove the # >>> vmalpha-lab >>> block from the hosts file
```
