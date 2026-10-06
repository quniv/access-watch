# access-watch

Lightweight, realtime monitoring of logins and remote access on a Linux
machine, with alerts pushed to Telegram. This is an **observation** tool: it
tells *you* what is happening on *your* machine. It does not block anyone and
makes no attempt to fight back against another party.

## What it watches

| Source | Catches | Latency |
|---|---|---|
| `journalctl -f` (user service) | logins, new sessions, `sudo`/`su`, failed auth, xrdp | near-instant |
| state timer (every 2 min) | established RDP/VNC/RustDesk connections, remote-access processes, watched users | up to ~2 min |
| auditd (optional, root) | reads of private files, commands run by a given user, firewall changes | near-instant |

Alerts go to a Telegram bot you control. Because they leave the machine the
moment an event fires, Telegram doubles as an off-box log that is harder to
quietly erase than local log files.

## Install (user-level, no root for the core)

```bash
git clone https://github.com/<you>/access-watch.git
cd access-watch
./install.sh
# edit ~/.config/access-watch/telegram.conf with your BOT_TOKEN and CHAT_ID
systemctl --user enable --now access-watch-auth.service
systemctl --user enable --now access-watch-state.timer
```

Get a bot token from `@BotFather` (`/newbot`). Get your chat id by messaging
the bot once and reading `chat.id` from
`https://api.telegram.org/bot<TOKEN>/getUpdates`.

## Optional: auditd layer (root)

Only this layer can observe actions by a higher-privileged user (e.g. an `it`
account) and reads of your files. It runs as root.

```bash
sudo apt install -y auditd audispd-plugins
sudo mkdir -p /etc/access-watch
sudo cp config/telegram.conf.example /etc/access-watch/telegram.conf
sudo chmod 600 /etc/access-watch/telegram.conf   # then edit it
sudo install -m700 audit/audit-telegram.sh /usr/local/sbin/audit-telegram.sh
sudo cp audit/access-watch.rules /etc/audit/rules.d/access-watch.rules
sudo cp audit/audisp-telegram.conf /etc/audit/plugins.d/audisp-telegram.conf
# edit the rules file: set your private path and 'it' uid (id -u it)
sudo augenrules --load
sudo systemctl restart auditd
```

## Honest limitations

Read these before relying on it.

- **This is not a defense.** It reports; it does not stop anyone. That is a
  deliberate choice: automatically blocking an IT/admin action on a
  company-owned machine is highly visible (Defender flags tampering, Intune
  marks the device non-compliant) and tends to cause more trouble for you than
  the thing you were worried about.
- **Root sits above you.** Anyone with root — including IT via a local admin
  account — can stop these services, edit the rules, or read the Telegram token
  out of the config. You cannot covertly surveil someone who has more privilege
  than you on the same box.
- **Defender Live Response is a blind spot.** It acts through the `mdatp` agent
  at kernel/cloud level and need not create a login session or `execve` that
  these watchers see.
- **Realtime means noise.** Tune the `case` filters in `watch-auth.sh` if cron
  or routine system activity is too chatty.

## The real fix for privacy

On a company-managed device, the reliable way to keep personal things private
is to keep them off the device entirely — personal matters on a personal
phone/laptop, this machine for work only. Monitoring tells you what happened;
separation means there is nothing of yours to find.

## Uninstall

```bash
./install.sh --uninstall
```

## License

MIT. Use at your own risk; see limitations above.
