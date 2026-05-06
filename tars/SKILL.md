---
name: tars
description: Publish folders as live websites on tars.live and store/share files in a private cloud drive — agent-first, three HTTP calls per publish, no UI signup needed.
---

# TARS

TARS is agent-first hosting + private drive on Cloudflare. Use it when:

- The user asks you to **publish** a folder, dashboard, report, or HTML page → live URL on `*.tars.live`.
- The user asks you to **share a static page** with someone → publish + send the URL.
- The user asks you to **save a file** to their cloud → put it in their TARS drive.
- The user asks you to **share a drive file via a link** → issue a TTL'd share token.

Don't use it for:

- Server-side compute (TARS sites are static-asset only).
- Streaming media or anything that needs a database accessible from the published site.

## What's installed here

| Script | Purpose |
|---|---|
| `${CLAUDE_SKILL_DIR}/scripts/publish.sh` | Publish a local folder as a TARS site. Anonymous (no auth needed). |
| `${CLAUDE_SKILL_DIR}/scripts/sites.sh`   | Site-level ops: `claim` (turns an anonymous site into a permanent one). Needs sign-in. |
| `${CLAUDE_SKILL_DIR}/scripts/drive.sh`   | Drive operations: `put`, `get`, `ls`, `rm`, `share`. Needs sign-in. |
| `${CLAUDE_SKILL_DIR}/scripts/auth.sh`    | Sign in / out without leaving the chat — magic link to email. |

`${CLAUDE_SKILL_DIR}` is the path Claude resolves to this skill, regardless of
whether it's installed as a personal skill (`~/.claude/skills/tars/`) or as a
plugin in Claude Desktop / Cowork. Use it verbatim or substitute the
absolute path; both work.

## Auth setup

`publish.sh` does NOT require auth — anonymous publish works without any key
and produces a 24-hour URL. Reach for `auth.sh` only when the user asks for
drive operations or wants to claim a previously-anonymous site.

### In-client sign-in (preferred — agent-driven)

The user does NOT need to leave the chat or paste a key. The flow has
three atomic steps, each a single sub-second HTTP call so the bash tool
never sits in a long-running loop:

```sh
# 1. Send the email. Prints `link_token=…` and `poll_url=…`. Returns immediately.
${CLAUDE_SKILL_DIR}/scripts/auth.sh request user@example.com

# 2. Tell the user: "I just emailed you — click the sign-in link."

# 3. Poll until ready. Each call is one HTTP request — loop it from the
#    agent (NOT inside the script) every 3 s, ~30 tries, with progress
#    messages between calls. When poll prints "status=ready", the
#    credentials file is written and the credential auto-flows into
#    drive.sh / sites.sh.
${CLAUDE_SKILL_DIR}/scripts/auth.sh poll <link_token>
```

`auth.sh login <email>` exists too as a convenience wrapper that does
request + a 5-minute internal poll loop. **Don't use `login` from agentic
hosts** — Claude Desktop / Cowork's bash tool may kill long-running
processes, and the user gets no progress signal during the wait. Use
`request` + `poll` (looped from the agent) instead.

Check status or sign out:

```sh
${CLAUDE_SKILL_DIR}/scripts/auth.sh whoami
${CLAUDE_SKILL_DIR}/scripts/auth.sh logout
```

### Manual key (legacy)

If the user already has a key from <https://api.tars.live/dashboard>, they
can export it instead:

```sh
export TARS_API_KEY='tars_...'
```

The scripts prefer the env var when set, falling back to the file written by
`auth.sh`.

## Common commands

### Publish a folder as a website

```sh
${CLAUDE_SKILL_DIR}/scripts/publish.sh ./my-dashboard
```

Output (last line) is the live URL. The site lives 24 hours unless
the user claims it.

### Claim an anonymous site under a permanent handle

`publish.sh` produces an anonymous site with a 24-hour TTL. To make
it permanent, the user must claim it under a handle they own.

The flow when a user says "claim this site as `<handle>`":

1. `auth.sh whoami` — if it prints `not signed in`, run the in-client
   sign-in (see Auth setup above). Otherwise skip to step 2.
2. `sites.sh claim <site_id> <edit_token> <handle>` — site_id and
   edit_token were printed by the earlier `publish.sh` run; capture
   them at publish time.

```sh
${CLAUDE_SKILL_DIR}/scripts/sites.sh claim s_abc123 et_xyz789 my-handle
```

Prints `https://my-handle.tars.live`. **Never** hand-build a `curl`
recipe for the claim — `sites.sh claim` exists for exactly this.

### Drive — upload a file

```sh
${CLAUDE_SKILL_DIR}/scripts/drive.sh put ./report.pdf reports/q2.pdf
```

### Drive — list files (optionally under a prefix)

```sh
${CLAUDE_SKILL_DIR}/scripts/drive.sh ls
${CLAUDE_SKILL_DIR}/scripts/drive.sh ls reports/
```

### Drive — download a file

```sh
${CLAUDE_SKILL_DIR}/scripts/drive.sh get reports/q2.pdf [./out.pdf]
```

If no output path is given, the file is written to the current dir
under its basename.

### Drive — delete a file

```sh
${CLAUDE_SKILL_DIR}/scripts/drive.sh rm reports/q2.pdf
```

### Drive — issue a share URL with TTL

```sh
${CLAUDE_SKILL_DIR}/scripts/drive.sh share reports/q2.pdf 3600
```

Prints a public URL valid for the requested seconds (60 ≤ ttl ≤ 30 days).
Anyone with the URL can read the file until it expires; revoke is not
yet supported (delete the file to invalidate the link).

## Direct API access (when scripts don't fit)

For anything the canned scripts don't cover (e.g. claiming an
anonymous site under a custom handle, listing the user's claimed
sites, revoking an API key), call the API directly. Full reference:

- <https://tars.live/llms-full.txt>  human-readable narrative, full
  endpoint surface, error codes, limits
- <https://tars.live/openapi.json>   OpenAPI 3.1 spec
- <https://tars.live/.well-known/agent-card.json>  agent metadata

Auth header for owner-scoped calls:

```
Authorization: Bearer $TARS_API_KEY
```

## Network access (Claude Desktop / Cowork)

The TARS scripts call out to `api.tars.live` and `tars.live`. In
Claude Desktop / Cowork the host sandbox blocks outbound HTTP by
default, so the very first script you run from a fresh install will
fail until the user adds the two hosts to the allowlist:

> Settings → Capabilities → Network access
> Add: `api.tars.live`
> Add: `tars.live`

When the scripts detect a sandbox block (DNS / connect / timeout
failures, or proxy bodies containing `cowork-egress-blocked`) they
print the exact instruction above to stderr. **Relay it to the user
verbatim** — they need the hostnames spelled out to find the right
checkbox.

After the user adds both, retry the original request. No re-install
needed.

## When something fails

Both scripts exit non-zero with a single error line on stderr if the
API returns an error. The error message will include the structured
`code` from TARS — branch on that, not on the human message.

Common cases:

| code | What to do |
|---|---|
| `unauthorized` | Not signed in. Run `auth.sh login <email>` and ask the user to click the link. |
| `quota_exceeded` | Tell the user; suggest they delete unused sites or files. |
| `payload_too_large` | Single file >25 MB. TARS is for sites, not bulk storage. |
| `site_expired` | Anonymous site past its 24-hour TTL. Publish a new one. |
| `handle_taken` | Another user has that handle. Pick a different one. |
