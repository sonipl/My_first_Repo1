# vCenter SSH Tunnel — Windows permanent setup

Reach **vc01.vmalpha.com** (vCenter) through **ac01** (`192.168.68.26`) from your Windows PC.

```text
Browser → localhost:8443 → SSH tunnel → ac01 → vc01.vmalpha.com:443
```

## One-command install (PowerShell as Administrator)

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
cd $env:USERPROFILE\Downloads
git clone https://github.com/sonipl/My_first_Repo1.git
cd My_first_Repo1\windows\vcenter-tunnel
.\install.ps1
```

Or if you already have the repo:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
cd C:\path\to\My_first_Repo1\windows\vcenter-tunnel
.\install.ps1
```

The installer will:
1. Copy tunnel scripts to `C:\Tools\vcenter-tunnel\`
2. Append SSH config to `%USERPROFILE%\.ssh\config`
3. Optionally add `vc01.vmalpha.com` to the Windows hosts file
4. Create a Task Scheduler job to start the tunnel at login (auto-reconnect)

## Manual install

### 1. Copy files

```powershell
mkdir C:\Tools\vcenter-tunnel -Force
Copy-Item start-tunnel.ps1, start-tunnel.bat C:\Tools\vcenter-tunnel\
```

### 2. Add SSH config

Append contents of `ssh-config-snippet` to `C:\Users\<YOU>\.ssh\config`

### 3. Test

```powershell
ssh -N vcenter-tunnel
```

Open: **https://localhost:8443**

### 4. Auto-start

Run `register-scheduled-task.ps1` as Administrator.

## After install

| What | Value |
|------|-------|
| vCenter URL | https://localhost:8443 |
| With hosts file | https://vc01.vmalpha.com |
| Jump host | psoni@192.168.68.26 |
| Log file | C:\Tools\vcenter-tunnel\tunnel.log |
| Stop tunnel | Task Scheduler → disable/end `vCenter SSH Tunnel` |
| Start manually | `C:\Tools\vcenter-tunnel\start-tunnel.bat` |

## SSH key (recommended)

Avoid password prompts on reconnect:

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
# Is tunnel listening?
netstat -an | findstr ":8443"

# View log
Get-Content C:\Tools\vcenter-tunnel\tunnel.log -Tail 30

# Test SSH to jump host
ssh ac01

# Test vCenter path from ac01
ssh ac01 "curl -k -I https://vc01.vmalpha.com"
```

## Uninstall

```powershell
Unregister-ScheduledTask -TaskName "vCenter SSH Tunnel" -Confirm:$false
Remove-Item -Recurse -Force C:\Tools\vcenter-tunnel
# Remove vcenter-tunnel and ac01 blocks from %USERPROFILE%\.ssh\config manually
# Remove 127.0.0.1 vc01.vmalpha.com from hosts file if added
```
