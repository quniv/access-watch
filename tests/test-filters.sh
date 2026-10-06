#!/usr/bin/env bash
# Offline tests for the owner/remote filtering in watch-auth.sh and
# watch-state.sh. No network, no journal: feeds sample log lines.
#   ./tests/test-filters.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/conf" <<CONF
BOT_TOKEN="x"
CHAT_ID="1"
OWNER_USER="quyet"
ALLOW_USERS="gdm, backup"
CONF
export ACCESS_WATCH_CONFIG="$TMP/conf"

# shellcheck source=../scripts/watch-auth.sh
source "$ROOT/scripts/watch-auth.sh"
SENT=""
send() { SENT="$1"; }

fail=0
# expect <alert|quiet> <journal line>
expect() {
  SENT=""
  handle_line "$2"
  local got=quiet; [ -n "$SENT" ] && got=alert
  if [ "$got" = "$1" ]; then printf 'ok    %-5s %s\n' "$1" "$2"
  else printf 'FAIL  want %s got %s: %s\n' "$1" "$got" "$2"; fail=1; fi
}

echo "== watch-auth: owner local activity is quiet"
expect quiet '    quyet : TTY=pts/0 ; PWD=/home/quyet ; USER=root ; COMMAND=/usr/bin/apt update'
expect quiet 'pam_unix(sudo:session): session opened for user root(uid=0) by quyet(uid=1000)'
expect quiet 'pam_unix(su:session): session opened for user root by quyet(uid=1000)'
expect quiet "New session 5 of user quyet."
expect quiet "New session '7' of user 'quyet' with class 'user' and type 'x11'."
expect quiet 'pam_unix(login:session): session opened for user quyet(uid=1000) by LOGIN(uid=0)'
expect quiet 'pam_unix(sudo:auth): authentication failure; logname=quyet uid=1000 euid=0 tty=/dev/pts/0 ruser=quyet rhost=  user=quyet'
expect quiet '    quyet : 3 incorrect password attempts ; TTY=pts/0 ; PWD=/home/quyet ; USER=root ; COMMAND=/bin/ls'
expect quiet "FAILED LOGIN (1) on '/dev/tty3' FOR 'quyet', Authentication failure"
expect quiet 'New session c1 of user gdm.'
expect quiet 'pam_unix(sshd:session): session opened for user quyet(uid=1000) by (uid=0)'

echo "== watch-auth: owner from a remote host still alerts"
expect alert 'Accepted password for quyet from 10.0.0.5 port 50022 ssh2'
expect alert 'Accepted publickey for quyet from 10.0.0.5 port 50022 ssh2: ED25519 SHA256:abc'
expect alert 'Failed password for quyet from 203.0.113.9 port 4242 ssh2'
expect alert 'pam_unix(sshd:auth): authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost=203.0.113.9  user=quyet'
expect alert 'pam_unix(xrdp-sesman:session): session opened for user quyet(uid=1000) by (uid=0)'
expect alert "FAILED LOGIN (1) on '/dev/pts/3' FROM '10.0.0.5' FOR 'quyet', Authentication failure"

echo "== watch-auth: other users always alert"
expect alert '      it : TTY=pts/1 ; PWD=/home/it ; USER=root ; COMMAND=/bin/cat /home/quyet/x'
expect alert 'pam_unix(sudo:session): session opened for user root(uid=0) by it(uid=1001)'
expect alert 'pam_unix(sudo:session): session opened for user quyet(uid=1000) by it(uid=1001)'
expect alert 'New session 9 of user it.'
expect alert 'pam_unix(su:session): session opened for user quyet(uid=1000) by root(uid=0)'
expect alert 'pam_unix(login:session): session opened for user it(uid=1001) by LOGIN(uid=0)'
expect alert 'Accepted password for it from 10.0.0.7 port 1 ssh2'
expect alert 'Failed password for invalid user admin from 198.51.100.2 port 2 ssh2'

echo "== watch-auth: unknown actor alerts, unrelated/cron lines stay quiet"
expect alert 'xrdp_wm_log_msg: connection established from 10.0.0.5 client foo'
expect quiet 'pam_unix(cron:session): session opened for user root(uid=0) by (uid=0)'
expect quiet 'Removed session 5.'

echo "== watch-state: who filtering"
eval "$(sed -n '/^filter_who()/,/^}/p' "$ROOT/scripts/watch-state.sh")"
got="$(filter_who <<'WHO'
quyet    seat0        2026-10-06 08:00 (login screen)
quyet    :0           2026-10-06 08:00 (:0)
quyet    tty2         2026-10-06 08:00 (tty2)
quyet    pts/0        2026-10-06 08:01
quyet    pts/3        2026-10-06 09:00 (10.0.0.5)
gdm      tty1         2026-10-06 07:59 (tty1)
it       pts/4        2026-10-06 09:05 (:1)
WHO
)"
want='quyet    pts/3        2026-10-06 09:00 (10.0.0.5)
it       pts/4        2026-10-06 09:05 (:1)'
if [ "$got" = "$want" ]; then echo "ok    who keeps remote owner + other users only"
else printf 'FAIL  who filter got:\n%s\n' "$got"; fail=1; fi

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME TESTS FAILED"; exit 1; }
