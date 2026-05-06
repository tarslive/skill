#!/usr/bin/env bash
# auth.sh — in-client magic-link bootstrap for TARS.
#
#   auth.sh login <email>    Request a sign-in link, then poll until the user
#                            clicks it; on success persists the api_key.
#   auth.sh whoami           Print the stored api_key prefix (or "not signed in").
#   auth.sh logout           Remove the credentials file.
#
# After `login` succeeds, publish.sh and drive.sh will pick the credential up
# automatically — no shell export needed.
set -euo pipefail

API="${TARS_API_BASE:-https://api.tars.live}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
"$(dirname "$0")/_ensure-jq.sh" || exit 1
JQ="${CLAUDE_PLUGIN_DATA:-$SKILL_DIR}/bin/jq"
[ -x "$JQ" ] || JQ="$SKILL_DIR/bin/jq"

# Where to persist the api_key. Plugin data dir if running as a plugin
# (Claude Desktop / Cowork / Code plugin install), else XDG config.
CREDS_DIR="${CLAUDE_PLUGIN_DATA:-${XDG_CONFIG_HOME:-$HOME/.config}/tars}"
CREDS_FILE="$CREDS_DIR/credentials"

die()  { echo "auth.sh: $*" >&2; exit 1; }
note() { echo "$*" >&2; }

usage() {
  cat >&2 <<EOF
usage:
  auth.sh login <email>    Request a sign-in link and wait for the user to click it.
  auth.sh whoami           Print the stored api_key prefix.
  auth.sh logout           Remove stored credentials.
EOF
  exit 2
}

login() {
  email="${1:-}"
  [ -n "$email" ] || usage

  body=$(printf '{"email":%s,"label":"Claude assistant"}' "$(printf '%s' "$email" | "$JQ" -Rs .)")
  resp=$(curl -fsS -X POST "$API/v1/auth/skill-link" \
    -H 'content-type: application/json' \
    -d "$body") || die "could not start sign-in (network or API down?)"

  link_token=$(echo "$resp" | "$JQ" -er '.link_token') || die "malformed response: $resp"
  poll_url=$(echo "$resp"  | "$JQ" -er '.poll_url')

  note "Sign-in email sent to $email."
  note "Click the link in your inbox. This window will pick up the credentials automatically."
  note "(Link expires in ~15 minutes.)"

  # Poll. Backoff: 2s × ~150 tries = 5 minutes max wait.
  tries=150
  while [ $tries -gt 0 ]; do
    poll=$(curl -fsS -H 'accept: application/json' "$poll_url" 2>/dev/null) || true
    status=$(echo "$poll" | "$JQ" -r '.status // empty' 2>/dev/null || true)
    if [ "$status" = "ready" ]; then
      api_key=$(echo "$poll" | "$JQ" -er '.api_key')
      api_key_prefix=$(echo "$poll" | "$JQ" -r '.api_key_prefix // empty')

      mkdir -p "$CREDS_DIR"
      umask 077
      printf '%s' "$api_key" > "$CREDS_FILE.tmp"
      mv "$CREDS_FILE.tmp" "$CREDS_FILE"
      chmod 600 "$CREDS_FILE"

      note "Signed in. Credentials stored in $CREDS_FILE."
      note "  api_key prefix: ${api_key_prefix:-tars_…}"
      return 0
    fi
    sleep 2
    tries=$((tries - 1))
  done

  die "timed out waiting for the user to click the email link"
}

whoami() {
  if [ ! -r "$CREDS_FILE" ]; then
    echo "not signed in"
    return 0
  fi
  key=$(cat "$CREDS_FILE")
  # api_key shape is `tars_` + 32 chars; surface the first 12 chars for safety.
  echo "${key:0:12}…"
}

logout() {
  if [ -f "$CREDS_FILE" ]; then
    rm -f "$CREDS_FILE"
    note "Removed $CREDS_FILE."
  else
    note "Nothing to remove."
  fi
}

cmd="${1:-}"; shift || true
case "$cmd" in
  login)  login "$@" ;;
  whoami) whoami ;;
  logout) logout ;;
  *)      usage ;;
esac
