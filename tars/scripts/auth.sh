#!/usr/bin/env bash
# auth.sh — in-client magic-link bootstrap for TARS.
#
# Subcommands:
#   request <email>   Send a magic link, print link_token + poll_url. Returns
#                     immediately. Use from agent-driven hosts.
#   poll <token>      One-shot poll. Prints "status=pending" or "status=ready"
#                     (and writes the api_key to the credentials file when ready).
#   login <email>     Convenience wrapper: request, then poll in a 5-minute
#                     blocking loop. For terminal use.
#   whoami            Print the stored api_key prefix (or "not signed in").
#   logout            Remove the credentials file.
#
# Once the credentials file exists, publish.sh / drive.sh / sites.sh pick it
# up automatically — no shell export needed.
set -euo pipefail

API="${TARS_API_BASE:-https://api.tars.live}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$(dirname "$0")/_net.sh"
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
  auth.sh request <email>   Send a magic-link email; prints link_token and poll_url.
  auth.sh poll <token>      One-shot poll. Prints status=pending or status=ready.
  auth.sh login <email>     request + blocking poll (terminal convenience).
  auth.sh whoami            Print the stored api_key prefix.
  auth.sh logout            Remove stored credentials.
EOF
  exit 2
}

# Persist a freshly-issued api_key from a poll response.
# Args: $1 = JSON poll response (must have .api_key, optionally .api_key_prefix)
persist_credentials() {
  local poll="$1"
  local api_key api_key_prefix
  api_key=$(echo "$poll" | "$JQ" -er '.api_key')
  api_key_prefix=$(echo "$poll" | "$JQ" -r '.api_key_prefix // empty')

  mkdir -p "$CREDS_DIR"
  umask 077
  printf '%s' "$api_key" > "$CREDS_FILE.tmp"
  mv "$CREDS_FILE.tmp" "$CREDS_FILE"
  chmod 600 "$CREDS_FILE"

  note "Signed in. Credentials stored in $CREDS_FILE."
  note "  api_key prefix: ${api_key_prefix:-tars_…}"
}

request() {
  email="${1:-}"
  [ -n "$email" ] || usage

  body=$(printf '{"email":%s,"label":"Claude assistant"}' "$(printf '%s' "$email" | "$JQ" -Rs .)")
  resp=$(curl -fsS -X POST "$API/v1/auth/skill-link" \
    -H 'content-type: application/json' \
    -d "$body") || { rc=$?; tars_curl_rc_explain $rc; die "could not start sign-in (network or API down?)"; }
  tars_check_body_for_egress "$resp"

  link_token=$(echo "$resp" | "$JQ" -er '.link_token') || die "malformed response: $resp"
  poll_url=$(echo  "$resp" | "$JQ" -er '.poll_url')

  # Plain key=value lines so the agent can grep/parse without jq.
  printf 'link_token=%s\n' "$link_token"
  printf 'poll_url=%s\n'   "$poll_url"
  note "Sign-in email sent to $email. Tell the user to click the link, then call: auth.sh poll $link_token"
}

poll() {
  token="${1:-}"
  [ -n "$token" ] || usage
  poll_url="$API/v1/auth/skill-link/$token"

  resp=$(curl -fsS -H 'accept: application/json' "$poll_url" 2>/dev/null) \
    || { rc=$?; tars_curl_rc_explain $rc; die "poll request failed"; }
  tars_check_body_for_egress "$resp"

  status=$(echo "$resp" | "$JQ" -r '.status // empty')
  case "$status" in
    pending)
      echo "status=pending"
      ;;
    ready)
      echo "status=ready"
      persist_credentials "$resp"
      ;;
    *)
      die "unexpected poll response: $resp"
      ;;
  esac
}

login() {
  email="${1:-}"
  [ -n "$email" ] || usage

  # Send the link via request(); capture link_token from its key=value output.
  req_out=$(request "$email")
  link_token=$(printf '%s' "$req_out" | sed -n 's/^link_token=//p')
  [ -n "$link_token" ] || die "could not parse link_token from request output"

  note "Polling — click the email link to complete sign-in."

  # 2 s × 150 = 5 min, same envelope as before.
  tries=150
  while [ $tries -gt 0 ]; do
    poll_out=$(poll "$link_token" 2>/dev/null || true)
    case "$poll_out" in
      *status=ready*) return 0 ;;
    esac
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
  request) request "$@" ;;
  poll)    poll "$@" ;;
  login)   login "$@" ;;
  whoami)  whoami ;;
  logout)  logout ;;
  *)       usage ;;
esac
