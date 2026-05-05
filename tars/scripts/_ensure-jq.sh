#!/usr/bin/env bash
# Ensures $SKILL_DIR/bin/jq exists. Called by publish.sh and drive.sh
# before any jq use. No-op when bin/jq is already present.
#
# Standalone script (NOT sourced) so its set -e and traps don't leak
# into callers, and so it can be invoked from any cwd.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JQ="$SKILL_DIR/bin/jq"
[ -x "$JQ" ] && exit 0

BASE_URL="${TARS_INSTALL_BASE:-https://tars.live/skill}"

die() { echo "ensure-jq: $*" >&2; exit 1; }

# 1. Detect platform.
os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"
case "$os-$arch" in
  darwin-arm64)              platform="darwin-arm64" ;;
  darwin-x86_64)             platform="darwin-x86_64" ;;
  linux-x86_64|linux-amd64)  platform="linux-x86_64" ;;
  linux-aarch64|linux-arm64) platform="linux-arm64" ;;
  *) die "unsupported platform: $os-$arch (TARS supports macOS arm64/x86_64 and Linux arm64/x86_64)" ;;
esac

# 2. Pick a SHA-256 tool.
if command -v sha256sum >/dev/null 2>&1; then
  sha_of() { sha256sum "$1" | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
  sha_of() { shasum -a 256 "$1" | awk '{print $1}'; }
elif command -v openssl >/dev/null 2>&1; then
  sha_of() { openssl dgst -sha256 -r "$1" | awk '{print $1}'; }
else
  die "no checksum tool found (need sha256sum, shasum, or openssl)"
fi

# 3. Fetch checksum manifest, parse expected sha for our platform.
checksums="$(curl -fsSL --retry 3 "$BASE_URL/jq-checksums.json")" \
  || die "could not fetch $BASE_URL/jq-checksums.json"
expected="$(printf '%s' "$checksums" | python3 -c \
  "import json,sys;print(json.loads(sys.stdin.read())['binaries']['$platform']['sha256'])")" \
  || die "platform $platform missing from manifest"

# 4. Fetch binary, verify, install atomically.
mkdir -p "$SKILL_DIR/bin"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl -fsSL --retry 3 "$BASE_URL/bin/jq-$platform" -o "$tmp" \
  || die "could not fetch $BASE_URL/bin/jq-$platform"
actual="$(sha_of "$tmp")"
[ "$actual" = "$expected" ] || die "jq checksum mismatch (expected $expected, got $actual)"
chmod +x "$tmp"
mv "$tmp" "$JQ"
trap - EXIT
"$JQ" --version >/dev/null 2>&1 || die "jq binary won't run on this platform"
