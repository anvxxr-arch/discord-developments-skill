---
name: discord-platform-api
description: Build bots, interactions, webhooks, and gateway clients.
version: 0.1.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [Discord, API, Gateway, Webhooks, OAuth2]
    related_skills: [discord-api-forensics, rest-graphql-debug]
---

# Discord Platform API

Platform-level reference for building against Discord: HTTP REST, Gateway
WebSocket, interactions, components, OAuth2, webhooks, voice, and monetization.
It is distilled notes from `https://docs.discord.com/developers/` — not a client
library, and it does not cover shard hosting, library selection, or app review.
Everything is reachable with plain HTTP + WebSocket; no SDK required.

## When to Use

- "Build/register a slash command", "add a button/modal", "respond to an interaction"
- "My bot gets 403 / 401 / 400 BAD REQUEST and I don't know why"
- "Set up an interactions endpoint URL" or "validate X-Signature-Ed25519"
- "Post to a channel via webhook", "webhook returns 204 / 400 / 401"
- "Which intent do I need?", "bot disconnects every N minutes", "resume vs re-identify"
- "OAuth2 install link", "client credentials grant", "webhook.incoming scope"
- "Embed is rejected", "message too long", "components v2 message fails"
- "Check entitlements / subscriptions / SKU purchases"

## Prerequisites

- A bot token from the app's **Bot** page; `client_id` + `client_secret` from **OAuth2** page;
  `public_key` for signature validation. Store as env vars, never inline.
- Base URL: `https://discord.com/api/v10` (current default; v9 available, v8 and below deprecated).
- Auth header forms, exactly one of:
  - `Authorization: Bot <token>`
  - `Authorization: Bearer <oauth2_access_token>`
  - `Authorization: Basic <base64(client_id:client_secret)>` — token endpoints only.
- Always send a `User-Agent` in the form `DiscordBot ($url, $versionNumber)`.

## How to Run

Fetch live pages with `web_extract` when a detail is missing — every page is also
served as markdown by appending `.md` (e.g. `/developers/topics/rate-limits.md`),
and `https://docs.discord.com/llms.txt` is the full page index. Drive API calls
through the `terminal` tool with `curl`, or `execute_code` for loops, bitmask
math, and pagination. Write helper scripts with `write_file` rather than retyping
long payloads. Read a chapter on demand with
`skill_view(name='discord-platform-api', file_path='references/<file>')`.

## Quick Reference

```
GET    /users/@me                                  # who is this token
GET    /users/@me/guilds                           # guilds the token can see
GET    /gateway                                    # wss url (no auth)
GET    /gateway/bot                                # wss + shards + session_start_limit
GET    /guilds/{guild.id}/channels
GET    /guilds/{guild.id}/roles
GET    /guilds/{guild.id}/members?limit=1000
GET    /guilds/{guild.id}/audit-logs?limit=50
POST   /channels/{channel.id}/messages
PATCH  /channels/{channel.id}/messages/{message.id}
DELETE /channels/{channel.id}/messages/{message.id}
POST   /channels/{channel.id}/messages/bulk-delete
POST   /channels/{channel.id}/threads               # forum/media post
POST   /channels/{channel.id}/threads/{thread.id}/...
PUT    /channels/{channel.id}/thread-members/@me
POST   /interactions/{interaction.id}/{interaction.token}/callback
PATCH  /webhooks/{application.id}/{interaction.token}/messages/@original
POST   /webhooks/{application.id}/{interaction.token}        # followup
POST   /webhooks/{webhook.id}/{webhook.token}                # execute, no auth header
POST   /applications/{application.id}/commands               # global command
POST   /applications/{application.id}/guilds/{guild.id}/commands
GET    /applications/{application.id}/entitlements
```

## Procedure

1. **Resolve the token before anything else.** Confirm identity and reach with
   `GET /users/@me` and `GET /users/@me/guilds`. A token that resolves but sees no
target guild is a membership problem, not a permissions problem.
2. **Decode any ID for free.** Snowflake → time:
   `ms = (int(id) >> 22) + 1420070400000`. Never call the API to guess an ID's age.
3. **Pick the transport.** Persistent bot → Gateway. Serverless/stateless app →
   Interactions Endpoint URL (webhook). The two are mutually exclusive for
   interactions; you cannot receive both ways for one app.
4. **Gateway:** `GET /gateway/bot` → connect `wss://gateway.discord.gg/?v=10&encoding=json`
   → wait for `op 10 Hello` → heartbeat every `heartbeat_interval` ms (first one
   after `interval * jitter`) → send `op 2 Identify` with `token`, `intents`, `properties`.
   Cache `session_id` and `resume_gateway_url` from `READY`.
5. **Interactions endpoint:** answer `PING` (`type: 0`) with `204`; validate
   `X-Signature-Ed25519` against `X-Signature-Timestamp` + raw body with the app's
   public key, else return `401`. Answer the user within **3 seconds** with
   callback `type: 4` (or `5` to defer), then edit `/webhooks/{app_id}/{token}/messages/@original`.
6. **Compose messages** with `content` ≤ 2000 chars, ≤ 10 embeds, `allowed_mentions`
   set explicitly whenever user text enters `content`.
7. **Verify by reading back.** Fetch the created message by id and print the embed/
   component skeleton; a 2xx from your sender is not proof of what landed.

## Pitfalls

- **A browser or absent User-Agent returns 403, not 401.** `403 code 40333`
  "internal network error" means UA, never token. Same for Node `fetch()` without
  an explicit `user-agent` header.
- **Intents are mandatory on v8+.** Omitting one silently drops every event under
  it. `GUILD_MEMBERS` and `MESSAGE_CONTENT` are privileged and off by default.
- **1000 IDENTIFYs per 24h across all shards** → the token is reset and all sessions
  terminated. Resume instead of re-identifying; resume does not count.
- **3-second interaction deadline**, token valid **15 minutes** afterwards. Missing
  the deadline invalidates the token — defer with `type: 5` instead of racing.
- **`SEND_MESSAGES` does nothing in threads.** Threads need `SEND_MESSAGES_IN_THREADS`.
- **Bulk delete** takes 2–100 ids, refuses anything older than 2 weeks with a 400,
  and answers `204` with an empty body (JSON parsers read that as failure).
- **Embed budget is two limits at once**: per-field (title 256, description 4096,
  field value 1024, 25 fields) and a **6000-char sum across all embeds** in the
  message. Exceed either and the whole request 400s.
- **`IS_COMPONENTS_V2` (flag `1 << 15`) forbids `content`/`embeds`/`poll`** — a
  components-v2 message may contain only `components`. It also cannot be unset later.
- **Forum/media channels reject direct POST** (`50008`); create a thread with the
  starter `message` instead.
- **`50001 Missing Access` vs `10003 Unknown Channel` are different answers.** Always
  send a deliberately fake id in the same batch as a control.
- **Webhook event endpoints must answer `204` within 3 seconds** or Discord retries
  with backoff for up to 10 minutes, then disables the URL.

## Verification

```bash
curl -s -H "Authorization: Bot $TOKEN" -H "User-Agent: DiscordBot (probe, 1.0)" \
  https://discord.com/api/v10/users/@me
```
A JSON user object with `bot: true` proves token + UA + version are all correct. A
`401` means the token; a `403` with `code: 40333` means the User-Agent.

## References

Load only the chapter a question actually needs:

- `references/http-api-basics.md` — versioning, auth, UA, errors, snowflakes, pagination, file upload.
- `references/formatting-and-cdn.md` — mention syntax, timestamp styles, CDN paths, signed URLs, file filters.
- `references/rate-limits.md` — header format, buckets, 429 handling, global limit, Cloudflare bans.
- `references/gateway.md` — connect, heartbeat, identify, resume, intents, sharding, compression.
- `references/interactions.md` — interaction types, callback types, 3s/15min rules, followups, endpoint security.
- `references/messages-and-components.md` — message/embed limits, flags, allowed_mentions, component types.
- `references/permissions.md` — bitwise flags, overwrite computation, implicit permissions, syncing.
- `references/channels-and-threads.md` — channel types, overwrite objects, thread lifecycle, forums.
- `references/webhooks.md` — execute webhook, query params, thread targeting, Slack/GitHub compat.
- `references/oauth2.md` — authorization code, client credentials, bot install, webhook.incoming, scopes.
- `references/voice.md` — voice state update flow, voice opcodes, DAVE/E2EE, close codes.
- `references/monetization.md` — SKUs, entitlements, subscriptions, premium buttons, test mode.
- `references/status-codes.md` — gateway opcodes, close codes, HTTP codes, JSON error codes.

For read-only forensics on an existing guild (ID resolution, permission denial,
forum enumeration, audit log attribution) use `discord-api-forensics` instead.
