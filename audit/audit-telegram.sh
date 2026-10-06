#!/usr/bin/env bash
# auditd dispatcher plugin: forwards matching audit events to Telegram in
# realtime. auditd pipes events to this script's stdin.
#
# Install (as root):
#   cp audit-telegram.sh /usr/local/sbin/audit-telegram.sh
#   chmod 700 /usr/local/sbin/audit-telegram.sh
#   mkdir -p /etc/access-watch && cp telegram.conf /etc/access-watch/telegram.conf
#   chmod 600 /etc/access-watch/telegram.conf
#   install plugin (see audisp-telegram.conf) then: systemctl restart auditd
#
# SECURITY NOTE: /etc/access-watch/telegram.conf holds your bot token and is
# readable by root. On a company machine, root (hence IT) can read it.
set -uo pipefail

CONF="/etc/access-watch/telegram.conf"
[ -r "$CONF" ] || exit 0
# shellcheck disable=SC1090
source "$CONF"
[ -n "${BOT_TOKEN:-}" ] && [ -n "${CHAT_ID:-}" ] || exit 0
HOST="${HOST_LABEL:-$(hostname)}"

send() {
  curl -s --max-time 15 \
    "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    --data-urlencode text="$1" >/dev/null 2>&1 || true
}

# Only forward events carrying one of our keys; collapse multi-line records.
while read -r line; do
  case "$line" in
    *"key=\"aw_"*|*"aw_private"*|*"aw_sensitive"*|*"aw_sudo"*|*"aw_it_exec"*|*"aw_firewall"*)
      send "🚨 ${HOST} audit: ${line}"
      ;;
  esac
done
