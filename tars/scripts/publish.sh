#!/usr/bin/env bash
# publish.sh <directory>
# Anonymous publish of a folder of static files to TARS. Prints the live URL.
set -euo pipefail

API="${TARS_API_BASE:-https://api.tars.live}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$(dirname "$0")/_net.sh"
"$(dirname "$0")/_ensure-jq.sh" || exit 1
JQ="${CLAUDE_PLUGIN_DATA:-$SKILL_DIR}/bin/jq"
[ -x "$JQ" ] || JQ="$SKILL_DIR/bin/jq"

dir="${1:-}"
[ -d "$dir" ] || { echo "usage: publish.sh <directory>" >&2; exit 2; }

die() { echo "publish.sh: $*" >&2; exit 1; }

# 1. Create draft (no auth).
resp=$(curl -fsSL -X POST "$API/v1/sites" -H 'content-type: application/json' -d '{}') \
  || { rc=$?; tars_curl_rc_explain $rc; die "could not create site (network or API down?)"; }
tars_check_body_for_egress "$resp"
site_id=$(echo "$resp" | "$JQ" -er '.id') || die "malformed create response: $resp"
edit_token=$(echo "$resp" | "$JQ" -er '.edit_token')
url=$(echo "$resp" | "$JQ" -er '.url')

# 2. Upload files. -F field=@path makes the multipart form-data field name
#    the file's path (which becomes its URL path under the site root).
# (No `mapfile` — keep this script bash-3.2 compatible for default macOS.)
files=()
while IFS= read -r f; do
  files+=("$f")
done < <(cd "$dir" && find . -type f | sed 's|^\./||')
[ "${#files[@]}" -gt 0 ] || die "no files in $dir"
args=()
for f in "${files[@]}"; do
  args+=( -F "$f=@$dir/$f" )
done
curl -fsS -X POST "$API/v1/sites/$site_id/files" \
  -H "Authorization: Bearer $edit_token" \
  "${args[@]}" > /dev/null \
  || { rc=$?; tars_curl_rc_explain $rc; die "file upload failed"; }

# 3. Publish.
curl -fsS -X POST "$API/v1/sites/$site_id/publish" \
  -H "Authorization: Bearer $edit_token" > /dev/null \
  || { rc=$?; tars_curl_rc_explain $rc; die "publish failed"; }

# 4. Surface the URL on the last line of stdout (machines parse this).
echo "Published $(echo "${files[@]}" | wc -w | tr -d ' ') file(s) to:"
echo "$url"
echo
echo "Site expires in 24 h unless claimed. To claim, sign in at"
echo "https://api.tars.live/sign-in.html and run:"
echo "  curl -X POST $API/v1/sites/$site_id/claim \\"
echo "    -H 'Authorization: Bearer \$TARS_API_KEY' \\"
echo "    -H 'content-type: application/json' \\"
echo "    -d '{\"edit_token\":\"$edit_token\",\"handle\":\"<your-handle>\"}'"
