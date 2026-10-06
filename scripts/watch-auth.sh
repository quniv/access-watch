#!/usr/bin/env bash
# Realtime watcher: follows the systemd journal and alerts on login / sudo /
# session / remote-desktop events as they are logged. Runs as a long-lived
# user service (see systemd/access-watch-auth.service).
#
# This is OBSERVATION ONLY. It reports to you; it does not block anything.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

send "🟢 <b>${HOST}</b>: access-watch auth monitor started ($(date '+%F %T %Z'))"

# -f follow, -n0 skip backlog, -o cat for clean lines.
# Narrow to the units/comms that carry access events to keep noise down.
journalctl -f -n0 -o cat \
    _COMM=sudo + _COMM=su + _COMM=login + _COMM=sshd \
    + _COMM=systemd-logind + _COMM=xrdp + _COMM=xrdp-sesman \
| while IFS= read -r raw; do
    line="$(printf '%s' "$raw" | esc)"

    case "$raw" in
      # Someone escalated to root via sudo *by* another user.
      *"session opened for user root"*"by "*)
        # Skip cron's own root sessions (very frequent, harmless).
        case "$raw" in
          *CRON*) : ;;
          *) send "🔴 <b>${HOST}</b> sudo → root:"$'\n'"<pre>${line}</pre>" ;;
        esac
        ;;

      # Explicit sudo command execution (records the actual command).
      *"sudo: "*" ; COMMAND="*)
        send "🧾 <b>${HOST}</b> sudo command:"$'\n'"<pre>${line}</pre>"
        ;;

      # New interactive session / accepted ssh / new logind session.
      *"Accepted "*|*"New session "*|*"session opened for user"*)
        case "$raw" in
          *CRON*) : ;;  # ignore cron session spam
          *) send "🔐 <b>${HOST}</b> new session:"$'\n'"<pre>${line}</pre>" ;;
        esac
        ;;

      # Failed auth attempts.
      *"authentication failure"*|*"Failed password"*|*"FAILED LOGIN"*)
        send "⚠️ <b>${HOST}</b> failed auth:"$'\n'"<pre>${line}</pre>"
        ;;

      # xrdp / remote-desktop connection chatter.
      *"xrdp"*"connect"*|*"xrdp"*"client"*)
        send "🖥️ <b>${HOST}</b> xrdp activity:"$'\n'"<pre>${line}</pre>"
        ;;
    esac
  done
