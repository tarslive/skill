---
name: tars
description: Publish folders as live websites at <handle>.tars.live and store/share files in a private cloud drive — agent-first, three HTTP calls per publish, no UI signup needed.
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

| Path | Purpose |
|---|---|
| `~/.claude/skills/tars/scripts/publish.sh` | Publish a local folder as a TARS site. Anonymous (no auth needed). |
| `~/.claude/skills/tars/scripts/drive.sh`   | Drive operations: `put`, `get`, `ls`, `rm`, `share`. Requires `TARS_API_KEY`. |
| `~/.claude/skills/tars/bin/jq`             | jq 1.8.1 (used by both scripts to parse JSON responses). |

## Auth setup

For drive operations and for re-publishing already-claimed sites, the user
needs a TARS API key. Steps to bootstrap:

1. Sign in at <https://api.tars.live/sign-in.html> (magic link sent to email).
2. On <https://api.tars.live/dashboard>, click "Create new key" and copy it.
3. Tell the user to set it for their shell:

   ```sh
   export TARS_API_KEY='tars_...'
   ```

   Persist it in `~/.zshrc` / `~/.bashrc` for future sessions.

`publish.sh` does NOT require `TARS_API_KEY` — anonymous publish works
without any auth and produces a 24-hour URL. After it prints the URL,
suggest the user claim the site from their dashboard if they want to
keep it.

## Common commands

### Publish a folder as a website

```sh
~/.claude/skills/tars/scripts/publish.sh ./my-dashboard
```

Output (last line) is the live URL. The site lives 24 hours unless
the user claims it.

### Drive — upload a file

```sh
~/.claude/skills/tars/scripts/drive.sh put ./report.pdf reports/q2.pdf
```

### Drive — list files (optionally under a prefix)

```sh
~/.claude/skills/tars/scripts/drive.sh ls
~/.claude/skills/tars/scripts/drive.sh ls reports/
```

### Drive — download a file

```sh
~/.claude/skills/tars/scripts/drive.sh get reports/q2.pdf [./out.pdf]
```

If no output path is given, the file is written to the current dir
under its basename.

### Drive — delete a file

```sh
~/.claude/skills/tars/scripts/drive.sh rm reports/q2.pdf
```

### Drive — issue a share URL with TTL

```sh
~/.claude/skills/tars/scripts/drive.sh share reports/q2.pdf 3600
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

## When something fails

Both scripts exit non-zero with a single error line on stderr if the
API returns an error. The error message will include the structured
`code` from TARS — branch on that, not on the human message.

Common cases:

| code | What to do |
|---|---|
| `unauthorized` | API key not set or wrong. Re-export `TARS_API_KEY` or have the user issue a fresh one. |
| `quota_exceeded` | Tell the user; suggest they delete unused sites or files. |
| `payload_too_large` | Single file >25 MB. TARS is for sites, not bulk storage. |
| `site_expired` | Anonymous site past its 24-hour TTL. Publish a new one. |
| `handle_taken` | Another user has that handle. Pick a different one. |
