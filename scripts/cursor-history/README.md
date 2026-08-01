# Import Cursor chat history from Mac mini

These scripts move Cursor **chat and agent history** from your Mac mini (`192.168.68.20`, user `psoni`) to another Mac.

> **Security:** Do not commit passwords. Use SSH keys when possible. Rotate any password shared in chat.

## Why the cloud agent can't do this directly

The Mac mini is on your home LAN (`192.168.68.20`). Cloud agents cannot reach private IPs. Run these scripts from a Mac on the **same network** (your laptop or the destination Mac).

## Quick start (3 commands)

On a Mac on your home network:

```bash
cd scripts/cursor-history
chmod +x *.sh

# 1. Pull history from Mac mini (prompts for SSH password)
./pull-from-macmini.sh psoni@192.168.68.20

# 2. Quit Cursor on THIS Mac (Cmd+Q), then import
./import-to-cursor.sh imports/cursor-history-*.tar.gz

# 3. Open Cursor — chats and agent threads should appear
```

## Manual SSH (if you prefer)

```bash
# Export on Mac mini
ssh psoni@192.168.68.20 'bash -s' < export-on-macmini.sh

# Download the archive (use the filename printed by export)
scp psoni@192.168.68.20:~/cursor-history-export-*.tar.gz ~/Downloads/

# Import locally (Cursor must be quit)
./import-to-cursor.sh ~/Downloads/cursor-history-export-*.tar.gz
```

## What gets transferred

| Data | Mac mini path |
|------|---------------|
| All chats + agents | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` |
| Per-project chats | `~/Library/Application Support/Cursor/User/workspaceStorage/` |
| Rules & settings | `~/.cursor/` |

## Troubleshooting

- **Chats don't show after import** — fully quit Cursor (Cmd+Q) and reopen. Reload (Cmd+R) is not enough.
- **Project-specific chats missing** — those are keyed to folder paths. Open the repo at the same path as on the Mac mini, or use the [Cursor Chat Transfer](https://open-vsx.org/extension/ibrahim317/cursor-chat-transfer) extension for selective import.
- **SSH connection refused** — enable Remote Login on Mac mini: System Settings → General → Sharing → Remote Login.
- **Cloud agent runs** — history at [cursor.com/agents](https://cursor.com/agents) is account-based and does not need Mac mini import.

## Set up SSH keys (recommended)

```bash
ssh-copy-id psoni@192.168.68.20
```

After that, `pull-from-macmini.sh` won't ask for a password.
