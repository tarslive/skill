#!/usr/bin/env bash
# sites.sh <subcommand> [args]
# Site-level operations on the TARS API. All subcommands need an api_key
# (env $TARS_API_KEY, or the credentials file written by auth.sh).
#
# Subcommands:
#   claim <site_id> <edit_token> <handle>
#       Permanently claim an anonymous site under <handle>.tars.live.
#       Prints the claimed URL on stdout.
set -euo pipefail

API="${TARS_API_BASE:-https://api.tars.live}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$(dirname "$0")/_net.sh"
"$(dirname "$0")/_ensure-jq.sh" || exit 1
JQ="${CLAUDE_PLUGIN_DATA:-$SKILL_DIR}/bin/jq"
[ -x "$JQ" ] || JQ="$SKILL_DIR/bin/jq"

# Pull api_key from $TARS_API_KEY first, else the credentials file.
CREDS_DIR="${CLAUDE_PLUGIN_DATA:-${XDG_CONFIG_HOME:-$HOME/.config}/tars}"
if [ -z "${TARS_API_KEY:-}" ] && [ -r "$CREDS_DIR/credentials" ]; then
  TARS_API_KEY="$(cat "$CREDS_DIR/credentials")"
fi

die()  { echo "sites.sh: $*" >&2; exit 1; }

usage() {
  cat >&2 <<EOF
usage:
  sites.sh claim <site_id> <edit_token> <handle>
EOF
  exit 2
}

require_signed_in() {
  if [ -z "${TARS_API_KEY:-}" ]; then
    cat >&2 <<EOF
sites.sh: not signed in.

Run the magic-link flow first:
  $SKILL_DIR/scripts/auth.sh request <user-email>
  # user clicks the email link
  $SKILL_DIR/scripts/auth.sh poll <link_token>   # repeat until status=ready
EOF
    exit 1
  fi
}

claim() {
  [ $# -eq 3 ] || usage
  site_id="$1"; edit_token="$2"; handle="$3"
  require_signed_in

  body=$("$JQ" -nc \
    --arg edit_token "$edit_token" \
    --arg handle     "$handle" \
    '{edit_token: $edit_token, handle: $handle}')

  resp=$(curl -fsS -X POST "$API/v1/sites/$site_id/claim" \
    -H "Authorization: Bearer $TARS_API_KEY" \
    -H 'content-type: application/json' \
    -d "$body") || { rc=$?; tars_curl_rc_explain $rc; die "claim request failed (network or API)"; }
  tars_check_body_for_egress "$resp"

  url=$(echo "$resp" | "$JQ" -er '.url') || die "malformed claim response: $resp"
  echo "Claimed $site_id as $handle:"
  echo "$url"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  claim) claim "$@" ;;
  *)     usage ;;
esac
