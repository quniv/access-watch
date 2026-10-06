#!/usr/bin/env bash
# One-time installer for access-watch (user-level watchers).
#
# What it does (NO root needed for the core install):
#   - copies scripts to ~/.local/share/access-watch/scripts
#   - installs systemd USER units (realtime auth watcher + state timer)
#   - creates the config dir and a 600-perm config from your example
#   - enables linger so the watchers run even when you are not logged in
#
# The optional auditd layer is root-level and NOT installed here; see README.
#
# Usage:
#   ./install.sh            # install / update
#   ./install.sh --uninstall
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARE_DIR="$HOME/.local/share/access-watch"
CFG_DIR="$HOME/.config/access-watch"
UNIT_DIR="$HOME/.config/systemd/user"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

uninstall() {
  log "Stopping and disabling services..."
  systemctl --user disable --now access-watch-auth.service 2>/dev/null || true
  systemctl --user disable --now access-watch-state.timer 2>/dev/null || true
  rm -f "$UNIT_DIR"/access-watch-auth.service \
        "$UNIT_DIR"/access-watch-state.service \
        "$UNIT_DIR"/access-watch-state.timer
  systemctl --user daemon-reload
  rm -rf "$SHARE_DIR"
  warn "Left config untouched at: $CFG_DIR"
  warn "Linger not disabled; run 'sudo loginctl disable-linger $USER' if you want."
  log "Uninstalled user-level watchers."
  exit 0
}

[ "${1:-}" = "--uninstall" ] && uninstall

# --- 1. scripts ---
log "Installing scripts to $SHARE_DIR"
mkdir -p "$SHARE_DIR/scripts"
install -m 0755 "$REPO_DIR/scripts/lib.sh"         "$SHARE_DIR/scripts/lib.sh"
install -m 0755 "$REPO_DIR/scripts/watch-auth.sh"  "$SHARE_DIR/scripts/watch-auth.sh"
install -m 0755 "$REPO_DIR/scripts/watch-state.sh" "$SHARE_DIR/scripts/watch-state.sh"

# --- 2. config ---
mkdir -p "$CFG_DIR"
chmod 700 "$CFG_DIR"
if [ ! -f "$CFG_DIR/telegram.conf" ]; then
  install -m 0600 "$REPO_DIR/config/telegram.conf.example" "$CFG_DIR/telegram.conf"
  warn "Created $CFG_DIR/telegram.conf from template."
  warn "EDIT IT NOW with your BOT_TOKEN and CHAT_ID before starting the service."
else
  log "Config already exists at $CFG_DIR/telegram.conf (left as-is)."
fi

# --- 3. systemd user units ---
log "Installing systemd user units to $UNIT_DIR"
mkdir -p "$UNIT_DIR"
install -m 0644 "$REPO_DIR/systemd/access-watch-auth.service"  "$UNIT_DIR/"
install -m 0644 "$REPO_DIR/systemd/access-watch-state.service" "$UNIT_DIR/"
install -m 0644 "$REPO_DIR/systemd/access-watch-state.timer"   "$UNIT_DIR/"
systemctl --user daemon-reload

# --- 4. linger so it runs without an active graphical session ---
if command -v loginctl >/dev/null 2>&1; then
  if ! loginctl show-user "$USER" 2>/dev/null | grep -q 'Linger=yes'; then
    log "Enabling linger (needs sudo once) so watchers run at boot..."
    sudo loginctl enable-linger "$USER" || warn "Could not enable linger; enable it manually."
  fi
fi

cat <<EOF

$(log "Install complete.")

Next steps:
  1. Edit your credentials:
       \$EDITOR $CFG_DIR/telegram.conf
  2. Start the watchers:
       systemctl --user enable --now access-watch-auth.service
       systemctl --user enable --now access-watch-state.timer
  3. Verify:
       systemctl --user status access-watch-auth.service
       systemctl --user list-timers | grep access-watch
       journalctl --user -u access-watch-auth.service -n 20 --no-pager

You should receive a Telegram "monitor started" message when the auth service
starts. Optional root-level auditd layer: see README.md.
EOF
