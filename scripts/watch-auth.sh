#!/usr/bin/env bash
# Realtime watcher: follows the systemd journal and alerts on login / sudo /
# session / remote-desktop events as they are logged. Runs as a long-lived
# user service (see systemd/access-watch-auth.service).
#
# The owner's (and ALLOW_USERS') own local activity is not alerted on. Anything
# from a remote host is, whoever it claims to be: someone using your account
# from elsewhere is exactly what this is meant to catch.
#
# This is OBSERVATION ONLY. It reports to you; it does not block anything.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# Patterns for the journal lines we care about (journalctl -o cat strips the
# "sudo:"/"sshd[123]:" prefix, so these match the message body only).
RE_SUDO_CMD='^[[:space:]]*([^[:space:]]+) : .*(COMMAND=|incorrect password)'
RE_PAM_OPEN='session opened for user ([^( ]+)(\(uid=[0-9]+\))? by ([^( ]*)'
RE_ACCEPTED='Accepted [^ ]+ for ([^ ]+) from ([^ ]+)'
RE_FAILED_PW='Failed [^ ]+ for (invalid user )?([^ ]+) from ([^ ]+)'
RE_LOGIND="New session '?[^ ']+'? of user '?([^ '.]+)"
RE_PAM_FAIL='authentication failure;.*logname=([^ ]*) .*ruser=([^ ]*) rhost=([^ ]*) +user=([^ ]*)'
RE_FAILED_LOGIN="FAILED LOGIN .* FOR '([^']+)'"

# classify <raw>: sets ACTOR (user responsible, may be empty if unknown) and
# REMOTE (1 if the event came from another host).
classify() {
  local raw="$1"
  ACTOR="" REMOTE=0
  if [[ $raw =~ $RE_SUDO_CMD ]]; then
    ACTOR="${BASH_REMATCH[1]}"
  elif [[ $raw =~ $RE_PAM_OPEN ]]; then
    # "by X" is who opened it (sudo/su caller). It is empty for sshd and
    # "LOGIN" for console logins; then the session's own user is the actor.
    ACTOR="${BASH_REMATCH[3]}"
    [ "$ACTOR" = "LOGIN" ] && ACTOR=""
    ACTOR="${ACTOR:-${BASH_REMATCH[1]}}"
  elif [[ $raw =~ $RE_ACCEPTED ]]; then
    ACTOR="${BASH_REMATCH[1]}"; REMOTE=1
  elif [[ $raw =~ $RE_FAILED_PW ]]; then
    ACTOR="${BASH_REMATCH[2]}"; REMOTE=1
  elif [[ $raw =~ $RE_LOGIND ]]; then
    ACTOR="${BASH_REMATCH[1]}"
  elif [[ $raw =~ $RE_PAM_FAIL ]]; then
    ACTOR="${BASH_REMATCH[1]:-${BASH_REMATCH[2]:-${BASH_REMATCH[4]}}}"
    [ -n "${BASH_REMATCH[3]}" ] && REMOTE=1
  elif [[ $raw =~ $RE_FAILED_LOGIN ]]; then
    ACTOR="${BASH_REMATCH[1]}"
    [[ $raw == *" FROM "* ]] && REMOTE=1
  fi
  # Anything xrdp touches is a remote-desktop session.
  [[ $raw == *xrdp* ]] && REMOTE=1
  return 0
}

# should_alert <raw>: decides after classify.
should_alert() {
  case "$1" in *CRON*|*"(cron:"*) return 1 ;; esac
  [ "$REMOTE" = 1 ] && return 0
  [ -z "$ACTOR" ] && return 0      # unknown actor: better a false alarm
  is_trusted_user "$ACTOR" && return 1
  return 0
}

handle_line() {
  local raw="$1" line
  classify "$raw"
  should_alert "$raw" || return 0
  line="$(printf '%s' "$raw" | esc)"

  case "$raw" in
    # Someone escalated to root via sudo/su.
    *"session opened for user root"*" by "*)
      send "🔴 <b>${HOST}</b> sudo → root:"$'\n'"<pre>${line}</pre>" ;;

    # Explicit sudo command execution (records the actual command).
    *" : "*"COMMAND="*)
      send "🧾 <b>${HOST}</b> sudo command:"$'\n'"<pre>${line}</pre>" ;;

    # New interactive session / accepted ssh / new logind session.
    *"Accepted "*|*"New session "*|*"session opened for user"*)
      send "🔐 <b>${HOST}</b> new session:"$'\n'"<pre>${line}</pre>" ;;

    # Failed auth attempts.
    *"authentication failure"*|*"Failed password"*|*"FAILED LOGIN"*|*"incorrect password"*)
      send "⚠️ <b>${HOST}</b> failed auth:"$'\n'"<pre>${line}</pre>" ;;

    # xrdp / remote-desktop connection chatter.
    *"xrdp"*"connect"*|*"xrdp"*"client"*)
      send "🖥️ <b>${HOST}</b> xrdp activity:"$'\n'"<pre>${line}</pre>" ;;
  esac
}

main() {
  send "🟢 <b>${HOST}</b>: access-watch auth monitor started for owner <b>$(printf '%s' "$OWNER" | esc)</b> ($(date '+%F %T %Z'))"

  # -f follow, -n0 skip backlog, -o cat for clean lines.
  # Narrow to the units/comms that carry access events to keep noise down.
  journalctl -f -n0 -o cat \
      _COMM=sudo + _COMM=su + _COMM=login + _COMM=sshd \
      + _COMM=systemd-logind + _COMM=xrdp + _COMM=xrdp-sesman \
  | while IFS= read -r raw; do
      handle_line "$raw"
    done
}

# Allow tests to source this file without starting the watcher.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then main; fi
