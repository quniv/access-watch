#!/usr/bin/env bash
# Shared helpers for access-watch scripts.

CONFIG_FILE="${ACCESS_WATCH_CONFIG:-$HOME/.config/access-watch/telegram.conf}"

if [ ! -r "$CONFIG_FILE" ]; then
  echo "access-watch: config not found or unreadable: $CONFIG_FILE" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${BOT_TOKEN:?BOT_TOKEN not set in config}"
: "${CHAT_ID:?CHAT_ID not set in config}"

HOST="${HOST_LABEL:-$(hostname)}"

# send <html-text>
send() {
  local text="$1"
  # Fail quietly on network issues; never block the watcher.
  curl -s --max-time 15 \
    "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d parse_mode="HTML" \
    -d disable_web_page_preview="true" \
    --data-urlencode text="$text" >/dev/null 2>&1 || true
}

# html-escape stdin (minimal: & < >)
esc() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}
