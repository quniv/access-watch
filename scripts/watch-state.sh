#!/usr/bin/env bash
# Periodic watcher: snapshots "who is logged in", open remote-desktop
# connections, and remote-access processes. Alerts only when something
# CHANGES since last run, so you are not spammed. Runs on a short timer
# (see systemd/access-watch-state.timer) as a complement to the realtime
# journal watcher — it catches state the journal does not phrase as a line,
# e.g. an established RDP/VNC/RustDesk socket.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/access-watch"
mkdir -p "$STATE_DIR"

# notify_if_changed <key> <current-text> <header>
notify_if_changed() {
  local key="$1" current="$2" header="$3"
  local f="$STATE_DIR/$key"
  local prev=""
  [ -f "$f" ] && prev="$(cat "$f")"
  if [ "$current" != "$prev" ]; then
    printf '%s' "$current" > "$f"
    # Only alert when the new state is non-empty (appearance of something),
    # but also report when something that WAS present disappears.
    if [ -n "$current" ]; then
      send "${header}"$'\n'"<pre>$(printf '%s' "$current" | esc)</pre>"
    elif [ -n "$prev" ]; then
      send "${header} — cleared"
    fi
  fi
}

# --- Who is logged in right now ---
CUR_WHO="$(who 2>/dev/null || true)"
notify_if_changed "who" "$CUR_WHO" "🔐 <b>${HOST}</b>: login sessions changed"

# --- Established remote-desktop connections (not just listening) ---
CUR_RDP="$(ss -tnp 2>/dev/null | grep -iE ':3389|:5900|:5938' | grep -vi listen || true)"
notify_if_changed "rdp" "$CUR_RDP" "🖥️ <b>${HOST}</b>: remote-desktop connection"

# --- Remote-access processes running ---
CUR_PROC="$(ps -eo user,pid,cmd 2>/dev/null \
  | grep -iE 'rustdesk|anydesk|teamviewer|x11vnc|vino|xrdp' \
  | grep -v grep || true)"
notify_if_changed "rproc" "$CUR_PROC" "⚠️ <b>${HOST}</b>: remote-access process"

# --- Watched users (from WATCH_USERS in config) ---
if [ -n "${WATCH_USERS:-}" ]; then
  IFS=',' read -ra users <<< "$WATCH_USERS"
  for u in "${users[@]}"; do
    u="$(echo "$u" | xargs)"   # trim
    [ -z "$u" ] && continue
    cur="$(who 2>/dev/null | grep -iw "$u" || true)"
    last1="$(last -F "$u" -n1 2>/dev/null | head -1 || true)"
    notify_if_changed "user_$u" "${cur}${last1}" \
      "👤 <b>${HOST}</b>: activity for user <b>$(printf '%s' "$u" | esc)</b>"
  done
fi
