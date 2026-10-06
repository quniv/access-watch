#!/usr/bin/env bash
# One-time installer for access-watch (user-level watchers).
#
# What it does (NO root needed for the core install):
#   - copies scripts to ~/.local/share/access-watch/scripts
#   - installs systemd USER units (realtime auth watcher + state timer)
#   - creates the config dir and a 600-perm config from your example
#   - enables linger so the watchers run even when you are not logged in
#
# The optional auditd layer is root-level and only installed with --audit.
#
# Usage:
#   ./install.sh            # install / update
#   ./install.sh --audit    # install the optional auditd layer (uses sudo)
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

install_audit() {
  # Paths in the rules file belong to the user being protected, so take them
  # from the invoking user's environment, not root's.
  local target_home="${AW_HOME:-$HOME}"
  if [ "$(id -u)" -eq 0 ] && [ -z "${AW_HOME:-}" ]; then
    warn "Run --audit as your normal user (it calls sudo itself), or set AW_HOME."
    exit 1
  fi
  if ! command -v augenrules >/dev/null 2>&1 && ! sudo test -x /sbin/augenrules; then
    warn "auditd not found. Install it first: sudo apt install -y auditd audispd-plugins"
    exit 1
  fi

  local target_uid="${AW_UID:-$(stat -c %u "$target_home" 2>/dev/null || true)}"
  if ! [[ $target_uid =~ ^[0-9]+$ ]] || [ "$target_uid" -eq 0 ]; then
    warn "Could not determine a non-root owner uid for $target_home; set AW_UID."
    exit 1
  fi

  log "Installing auditd layer for home: $target_home (uid $target_uid)"
  [ -d "$target_home/private" ] || warn "$target_home/private does not exist yet; create it so the watch applies."

  sudo mkdir -p /etc/access-watch
  sudo chmod 700 /etc/access-watch
  if sudo test -f /etc/access-watch/telegram.conf; then
    log "/etc/access-watch/telegram.conf already exists (left as-is)."
  elif [ -f "$CFG_DIR/telegram.conf" ]; then
    sudo install -m 0600 "$CFG_DIR/telegram.conf" /etc/access-watch/telegram.conf
  else
    sudo install -m 0600 "$REPO_DIR/config/telegram.conf.example" /etc/access-watch/telegram.conf
    warn "Created /etc/access-watch/telegram.conf from template; edit it with sudo."
  fi

  sudo install -m 0700 "$REPO_DIR/audit/audit-telegram.sh" /usr/local/sbin/audit-telegram.sh

  sed -e "s|@HOME@|${target_home}|g" -e "s|@UID@|${target_uid}|g" \
      "$REPO_DIR/audit/access-watch.rules" \
    | sudo tee /etc/audit/rules.d/access-watch.rules >/dev/null
  sudo chmod 0640 /etc/audit/rules.d/access-watch.rules

  local plugin_dir=/etc/audit/plugins.d
  sudo test -d "$plugin_dir" || plugin_dir=/etc/audisp/plugins.d
  sudo install -m 0640 "$REPO_DIR/audit/audisp-telegram.conf" "$plugin_dir/audisp-telegram.conf"

  sudo augenrules --load
  sudo systemctl restart auditd || sudo service auditd restart
  log "auditd layer installed. Rules: /etc/audit/rules.d/access-watch.rules"
  exit 0
}

[ "${1:-}" = "--uninstall" ] && uninstall
[ "${1:-}" = "--audit" ] && install_audit

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

# Record who owns this machine so the owner's own local activity is not
# alerted on. Only fills it in when missing or empty; never overrides.
OWNER_NAME="$(id -un)"
if ! grep -qE '^OWNER_USER="[^"]+"' "$CFG_DIR/telegram.conf"; then
  sed -i '/^OWNER_USER=/d' "$CFG_DIR/telegram.conf"
  printf 'OWNER_USER="%s"\n' "$OWNER_NAME" >> "$CFG_DIR/telegram.conf"
  log "Set OWNER_USER=\"$OWNER_NAME\" in $CFG_DIR/telegram.conf"
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
