#!/usr/bin/env bash
# Network-failure helpers for the TARS skill. Sourced by publish.sh,
# drive.sh, auth.sh, and _ensure-jq.sh. Don't `set -e` or install traps
# here — those would leak into callers.
#
# Why this file exists:
# Claude Desktop / Cowork sandbox outbound HTTP by default. When the
# allowlist is missing, the failure mode looks like a generic curl
# failure but the cause is policy, not connectivity. Turn that into a
# specific, agent-friendly instruction so the user knows exactly which
# Settings page to open.

# Print the egress-allowlist instruction to stderr. The wording is
# deliberately phrased so the agent can relay it to the user verbatim.
tars_egress_help() {
  cat >&2 <<'HELP'

TARS: outbound network access is blocked.

If you're running this in Claude Desktop or Cowork, the sandbox blocks
outbound HTTP by default. Two hosts must be allowed before TARS can
work:

  Settings → Capabilities → Network access
  Add: api.tars.live    (the TARS API)
  Add: tars.live        (the one-time jq binary fetch)

Once both are added, re-run the original request.

If you're not in a sandboxed host, this is a plain network failure —
check connectivity to api.tars.live and retry.
HELP
}

# tars_curl_rc_explain <rc>
# If curl's exit code matches a known network-block signature, print
# the egress-allowlist instruction and exit 1. Otherwise return 0 so
# the caller can report the real error itself.
#
# Curl exit codes handled:
#   6  — Could not resolve host (DNS blocked / no resolver)
#   7  — Failed to connect (TCP blocked)
#   28 — Operation timed out
#   35 — TLS connect error (often a TLS-intercepting block)
tars_curl_rc_explain() {
  case "${1:-0}" in
    6|7|28|35)
      tars_egress_help
      exit 1
      ;;
  esac
}

# tars_check_body_for_egress <response-body>
# Some sandboxes pass the curl request through and inject an error
# body on a 2xx response. Scan for known markers; on hit, print the
# instruction and exit 1.
tars_check_body_for_egress() {
  case "${1:-}" in
    *cowork-egress-blocked*|*cowork_egress_blocked*|*egress-blocked*|*"network access is blocked"*)
      tars_egress_help
      exit 1
      ;;
  esac
}
