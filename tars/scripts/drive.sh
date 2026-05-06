#!/usr/bin/env bash
# drive.sh <subcommand> [args]
# Subcommands: put, get, ls, rm, share. All require TARS_API_KEY.
set -euo pipefail

API="${TARS_API_BASE:-https://api.tars.live}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$(dirname "$0")/_net.sh"
"$(dirname "$0")/_ensure-jq.sh" || exit 1
JQ="${CLAUDE_PLUGIN_DATA:-$SKILL_DIR}/bin/jq"
[ -x "$JQ" ] || JQ="$SKILL_DIR/bin/jq"

# Pull the api key from $TARS_API_KEY, else the credentials file written by
# auth.sh (plugin-data dir if running as a plugin, else ~/.config/tars/).
CREDS_DIR="${CLAUDE_PLUGIN_DATA:-${XDG_CONFIG_HOME:-$HOME/.config}/tars}"
if [ -z "${TARS_API_KEY:-}" ] && [ -r "$CREDS_DIR/credentials" ]; then
  TARS_API_KEY="$(cat "$CREDS_DIR/credentials")"
fi
if [ -z "${TARS_API_KEY:-}" ]; then
  echo "drive.sh: not signed in. Run 'auth.sh login <email>' or export TARS_API_KEY." >&2
  exit 1
fi

# Preflight: surface sandbox network blocks before doing real work, so the
# user gets the egress-allowlist instruction instead of a generic curl
# failure mid-operation.
preflight=$(curl -fsS --connect-timeout 5 --max-time 10 "$API/v1/health" 2>/dev/null) \
  || { rc=$?; tars_curl_rc_explain $rc; }
tars_check_body_for_egress "${preflight:-}"

AUTH="Authorization: Bearer $TARS_API_KEY"

usage() {
  cat >&2 <<EOF
usage:
  drive.sh put <local-file> <remote-path>
  drive.sh get <remote-path> [output-file]
  drive.sh ls  [prefix]
  drive.sh rm  <remote-path>
  drive.sh share <remote-path> <ttl-seconds>
EOF
  exit 2
}

# URL-encode a path segment (preserves slashes between segments).
urlenc_path() {
  python3 -c 'import sys,urllib.parse;print("/".join(urllib.parse.quote(s,safe="") for s in sys.argv[1].split("/")))' "$1"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  put)
    [ $# -eq 2 ] || usage
    local_file="$1"; remote="$2"
    [ -f "$local_file" ] || { echo "drive.sh put: $local_file not found" >&2; exit 1; }
    curl -fsS -X PUT "$API/v1/drive/files/$(urlenc_path "$remote")" \
      -H "$AUTH" \
      --data-binary "@$local_file" | "$JQ" .
    ;;

  get)
    [ $# -ge 1 ] || usage
    remote="$1"; out="${2:-$(basename "$remote")}"
    curl -fsS -o "$out" -w "%{http_code}\n" \
      -H "$AUTH" \
      "$API/v1/drive/files/$(urlenc_path "$remote")" \
      | { read -r code; [ "$code" = "200" ] || { echo "drive.sh get: HTTP $code" >&2; rm -f "$out"; exit 1; }; }
    echo "Wrote $out"
    ;;

  ls)
    prefix="${1:-}"
    if [ -n "$prefix" ]; then
      curl -fsS -G --data-urlencode "prefix=$prefix" -H "$AUTH" "$API/v1/drive/files"
    else
      curl -fsS -H "$AUTH" "$API/v1/drive/files"
    fi | "$JQ" '.files | map({path, size, content_type, updated_at})'
    ;;

  rm)
    [ $# -eq 1 ] || usage
    remote="$1"
    curl -fsS -o /dev/null -w "%{http_code}\n" -X DELETE -H "$AUTH" \
      "$API/v1/drive/files/$(urlenc_path "$remote")" \
      | { read -r code; [ "$code" = "204" ] || { echo "drive.sh rm: HTTP $code" >&2; exit 1; }; }
    echo "Removed $remote"
    ;;

  share)
    [ $# -eq 2 ] || usage
    remote="$1"; ttl="$2"
    curl -fsS -X POST "$API/v1/drive/share-tokens" \
      -H "$AUTH" -H 'content-type: application/json' \
      -d "$(printf '{"paths":["%s"],"expires_in_seconds":%d}' "$remote" "$ttl")" \
      | "$JQ" '{url, expires_at, paths}'
    ;;

  *)
    usage
    ;;
esac
