---
name: discord-api-forensics
description: "Resolve Discord IDs, bots, and channel permissions."
version: 0.1.0
author: Hermes
license: MIT
metadata:
  hermes:
    tags: [Discord, Forensics, Permissions, API]
    related_skills: [fudcourt-development, rest-graphql-debug]
---

# Discord API Forensics

Answer "what is this ID, does it exist, and can my bot see it" using the REST API
instead of guessing. Everything here is read-only until the last section.

## When to Use

- User pastes a bare long numeric ID and asks what it is
- A bot returns 403 / "Missing Access" and you need to know whether the channel
  exists, whether the bot is a member, or whether a permission overwrite denies it
- You need to enumerate a guild's channels, roles, or forum posts
- You need to know which bot token on this host can see a given channel

## Procedure

### 1. Identify the ID type before spending any API call

Discord IDs are snowflakes: 17–20 digit decimals. Decode the creation time first —
it is free and it immediately tells you whether the ID is plausible for the guild
you think it belongs to.

```python
ms = (int(id) >> 22) + 1420070400000   # epoch ms
```

Compare that timestamp against known channel/guild IDs in the same server. An ID
that predates the guild's own creation is not from that guild. A channel that is
newer than every other channel is a recently hand-made one, which usually means it
is **not** wired into any code path.

A bare long positive integer in a chat message is almost always a Discord snowflake.
Telegram chat IDs are negative (groups) or short, and Telegram thread/topic IDs are
small integers — so an 18-digit positive ID is Discord until proven otherwise.

### 2. Find every bot token on the host before concluding "no access"

This host runs more than one Discord bot, and they are members of **different
guilds**. Concluding from one token that a channel is invisible is a wrong answer
that costs a round trip with the user.

Check, in this order:

```bash
grep -h 'DISCORD_BOT_TOKEN' ~/.hermes/.env
grep -h 'FUDCOURT_BOT_TOKEN' /home/dwizzy/.config/fudcourt/env
```

Resolve each token's identity and guilds before using it:

```bash
curl -s -H "Authorization: Bot $TOKEN" https://discord.com/api/v10/users/@me
curl -s -H "Authorization: Bot $TOKEN" https://discord.com/api/v10/users/@me/guilds
```

The bot that is a member of the target's guild is the one that can answer. Try each
candidate; report which bot succeeded.

**A missing env NAME is not a missing credential — read the unit before declaring an
outage.** The same bot token lives under different keys in different files
(`DISCORD_TOKEN` vs `FUDCOURT_BOT_TOKEN` vs `DISCORD_BOT_TOKEN`), so grepping one spelling,
finding nothing, and reporting "service FAILED, token missing from env, no backup" is a
fabricated outage: the credential was present under another key the whole time. Before
any down/red claim, run `systemctl --user is-active <unit>` + `systemctl --user cat <unit> |
grep EnvironmentFile` and resolve the token through the file the unit ACTUALLY names — and
notice that a healthy fail-quiet receiver proves nothing in either direction. A claim about
service state is a measurement, not an inference from an incomplete grep.

### 3. Run the control test — this is the whole technique

You cannot distinguish "channel does not exist" from "bot cannot see it" without a
reference point. Request a definitely-fake ID in the same batch:

```bash
for id in 1559255828014440579 1111111111111111111; do
  curl -s -H "Authorization: Bot $TOKEN" "https://discord.com/api/v10/channels/$id"
done
```

- fake ID → `{"code": 10003, "message": "Unknown Channel"}`
- target ID → `{"code": 50001, "message": "Missing Access"}`

**`10003` on the control plus `50001` on the target proves the channel EXISTS and the
bot lacks permission.** Without the control both answers look like "error" and you
will report the wrong conclusion.

### 4. Discriminate the ID kind with the three object endpoints

| Endpoint | "unknown" code | Meaning if that code returns |
|---|---|---|
| `/channels/{id}` | `10003 Unknown Channel` | not a channel |
| `/users/{id}` | `10013 Unknown User` | not a user |
| `/guilds/{id}` | `10004 Unknown Guild` | not a guild |

If `/channels/{id}` returns `50001` while `/users` and `/guilds` return their
specific unknown codes, the ID is a channel the bot cannot see. If `/channels`
returns `10003` too, the ID is not a channel at all.

### 5. Check channel type before trying to write

`type` matters more than anything else when composing a request:

| type | kind |
|---|---|
| 0 | text |
| 2 | voice |
| 4 | category |
| 5 | announcement |
| 13 | stage |
| **15** | **forum** |

**A forum channel (type 15) rejects direct message POST** with
`50008 Cannot send messages in a non-text channel`. That is correct behaviour, not a
permission bug. To post, create a thread instead:

```
POST /channels/{forum_id}/threads
{"name": "<post title>", "message": {"content": "<body>"}}
```

**The starter `message` is required** — a thread POST carrying only `name` is rejected, so compose the first message before the call rather than discovering the requirement from the error.

Never conclude "the bot cannot write" from a `50008` — check `type` first.

### 6. Decode permission overwrites when access is denied but the bot is a member

`permission_overwrites[]` entries carry `allow`/`deny` bitmasks. Decode them:

```python
v = 1049600
[1 << i for i in range(64) if v >> i & 1]   # -> [10, 20]
```

Bit 10 = `VIEW_CHANNEL` (1024), bit 20 = `CONNECT` (1048576). A deny of `1049600`
means view + connect denied for that role. Resolve role names with
`/guilds/{gid}/roles`, and the bot's own roles with
`/guilds/{gid}/members/{bot_id}` — a bot with Administrator bypasses overwrites, so
an Administrator bot that still gets `50001` is **not a member of that guild**.

### 7. Reading forum content

Forum posts live in threads, so `/channels/{forum}/messages` returns nothing useful.
Enumerate them:

```
GET /guilds/{gid}/threads/active                    # filter parent_id == forum id
GET /channels/{forum}/threads/archived/public?limit=20
GET /channels/{thread_id}/messages?limit=5
```

Attachment-only posts have `content: ""` — read `attachments[]` and `embeds[]` rather
than concluding the post is empty.

**Before planning a write into an existing thread, read its `thread_metadata`.** A thread
carries `archived` and `locked` booleans; a locked thread rejects posts and an archived one
must be unarchived first. `type` distinguishes the kinds — `10` announcement, `11` public,
`12` private — and only a public thread is postable by a bot without an invite. Confirm both
on the thread object before promising that automation can target it: a bot that resolves the
thread fine and then fails on POST looks like a permissions problem when it is a thread-state
problem, and the two have completely different fixes.

### 8. Enumerate the guild once and cache the shape

```
GET /guilds/{gid}/channels
```

Sort by `parent_id` then `position` and print the channel `type` beside each name.
Duplicate names across categories are common and intentional — two channels named
identically under different categories are two different channels, so always report
the **ID plus category**, never the name alone.

### 9. Audit an opt-in role / signal-distribution setup

When the ask is "does role X exist / are the roles right", a role list is not the
answer. Four independent things must line up, and each one fails silently alone:

| Check | How | Failure mode if skipped |
|---|---|---|
| `mentionable` | role object's `mentionable` field | only an Administrator bot can ping it; webhooks and other bots fail silently |
| subscribers | `/guilds/{gid}/members?limit=1000`, count the role id | an opt-in role with 0 members notifies nobody |
| overwrite wiring | scan every channel's `permission_overwrites[].id` for the role id | the role is decorative and gates nothing |
| code wiring | grep the repo for the role id and its name | no automation ever reads it |

Report all four. "The role exists" is a true statement that still leaves the user's
feature broken, and it buys a second round trip.

**Distinguish rename from create by diffing IDs, not names.** An unchanged id with a
changed name was renamed in place; a new id is a new role. When the user says "I made
a new role, check again", diff the id set against the previous read — otherwise a
rename reads as a creation and a creation reads as a rename, and you report the wrong
delta.

Full recipe with exact calls: `references/optin-role-audit.md`.

### 10. Audit a guild's thread coverage

An ambiguous request to "check the other threads" while a Discord guild is the active
surface means a coverage sweep of forum threads, not a code or threat hunt. Produce the
map read-only, then ask before any write:

```
GET /guilds/{gid}/threads/active                          # every active thread
GET /channels/{forum}/threads/archived/public?limit=50    # per forum channel
GET /channels/{thread_id}/messages?limit=2                # who authored what
```

Age every thread by decoding `last_message_id` as a snowflake (same formula as step 1).
Verdicts the sweep surfaces, each invisible without it:

- **last-message age ≈ thread creation age** → the automation the thread was made for
  never ran, or died on day one. A thread holding only its starter post is a dead
  watcher, not a quiet day; per-forum archive dates mark when activity stopped.
- **two active threads with the same name** → a config trap: automation writes one copy
  while readers watch the other. Compare authorship (which bot vs which human) and
  creation time before naming the survivor; re-pointing the automation is a code change,
  deleting a thread is a write to a live server.
- **a thread's parent forum contradicts the documented routing table** → routing drift.
  Verify against the config table, not vibes; report before touching anything.

**Print the parent forum by ID and resolve it through the channel map — never by its
display name.** Two forum channels on this server share the display name
`autosignal-"beta"` (one under the CEX category, one under DEX), so reading the parent
name alone manufactures a routing-drift finding that does not exist. This is the
section-8 rule ("ID plus category, never the name alone") applied to thread parents,
where the collision is easier to hit because forum display names repeat across
categories.

## Webhook posts (anti-spam feed forward)

A webhook post attributes to the webhook's own identity (e.g. name "Fox Feed")
rather than the bot, so Discord treats it as an approved integration instead of
a user agent hammering the REST API — this is the path when a bot's message
volume starts looking like spam. Post to:

```
POST https://discord.com/api/v10/webhooks/{webhook_id}/{webhook_token}
POST https://discord.com/api/v10/webhooks/{webhook_id}/{webhook_token}?thread_id={id}
```

No `Authorization` header — the URL carries the token. `204` = posted.

- **One webhook can serve every thread of its parent channel.** Create the
  webhook in a PARENT forum channel (`POST /channels/{parent}/webhooks`), then
  aim each post at a specific thread with `?thread_id={thread_id}`. Verified:
  one webhook created in forum `kol-wathcer` posted `204` into 13 different KOL
  threads this way. The webhook's own `channel_id` is the parent; the
  `?thread_id=` query param redirects the post into the thread.
- **A webhook can only reach threads under ITS parent.** A `thread_id` whose
  parent is a different forum returns `400 {"code":10003,"message":"Unknown Channel"}`.
  Posting into a thread needs a webhook whose parent is that thread's forum, so
  N forums need N webhooks (`notifier` fomo + `notifier` mexc + `kol-wathcer` = 3).
- **Create webhook directly in a thread is rejected.** `POST /channels/{thread}/webhooks`
  → `404 {"code":10003,"message":"Unknown Channel"}`. Create in the parent and
  use `?thread_id=`.
- **`401 {"code":0}` on `POST /channels/{parent}/webhooks` is MISSING PERMISSION, not a
  bad token** — the bot needs `MANAGE_WEBHOOKS` in that channel. Retry after a
  permission grant; the same call then returns the webhook object. An older stored
  webhook token that answers `403` on GET is revoked/deleted — create a fresh one
  rather than reusing it.
- **Webhook tokens in env vars go stale.** A `FUDCOURT_FORUM_WEBHOOK` /
  `FUDCOURT_MIRROR_WEBHOOKS` token can be revoked while the webhook object still
  lists; validate by `GET /webhooks/{id}/{token}` (a live one returns the object)
  before trusting it.
- **Read a webhook post back by `webhook_id`.** `GET /channels/{thread}/messages`
  shows `author.username` = webhook name and `webhook_id` set when the webhook
  authored it, `author.bot` true either way — distinguish bot vs webhook by
  `webhook_id`, not by the `bot` flag.

- **Webhook posts support `message_reference` for reply threading.** Include
  `message_reference: {message_id: "DISCORD_MESSAGE_ID"}` in the webhook payload
  to post as a reply to an existing message. The referenced message must live in
  the same thread; a `message_reference` pointing at a missing or foreign message
  is silently dropped — the post still lands, just not as a reply. Fetch the
  destination thread's recent messages first to resolve the target id, and store
  the delivered post's own id so the next item in the chain can reference it.

- **Webhook `username` + `avatar_url` override the webhook's registered identity.**
  The webhook payload accepts `username` (string) and `avatar_url` (avatar URL
  string); when present, the post attributes to that name and avatar instead of
  the webhook's own. Use this to attribute a forward to its original sender
  rather than the webhook bot. Discord allows this only for webhook posts — a
  bot-token POST cannot override the bot's identity. `avatar_url` must be a
  direct image URL; a Discord-attached avatar (`attachment://`) is not accepted
  here.

### 11. Attribute a change: the guild audit log

"This thread/channel/webhook vanished — did we do it?" is answered by the audit log,
not by inference. `GET /guilds/{gid}/audit-logs?limit=50[&action_type=<n>][&before=<entry_id>]`
(needs `VIEW_AUDIT_LOG`; newest first, `before`/`after` paginate). Each entry carries
`action_type`, `target_id`, `user_id`, and its own snowflake `id` — decode that `id` with
the step-1 formula to get the minute the change happened.

| action_type | event |
|---|---|
| 10 / 11 / 12 | CHANNEL_CREATE / UPDATE / DELETE |
| 50 | WEBHOOK_CREATE |
| 72 / 73 | MESSAGE_DELETE / MESSAGE_BULK_DELETE |
| 110 / 111 / 112 | THREAD_CREATE / UPDATE / DELETE |

- **Resolve `user_id` against `GET /users/@me` for EVERY bot token on the host before
  blaming the automation.** A thread deleted by the human operator (a real user id) and
  one deleted by the bot (the token's own id) look identical in the channel list; only the
  log separates them, and the wrong conclusion sends you debugging a pipeline that behaved
  correctly.
- **A burst of `10003 Unknown Channel` on webhook deliveries means the DESTINATION was
  deleted, not that the webhook is broken.** Re-check the target with `/channels/{id}` and
  `/guilds/{gid}/threads/active` before touching the sender or its token; the same read
  confirms the actor's delete from the other side.
- **Audit-log reads are guild-wide and cheap** — filter by `action_type` when hunting one
  class (thread deletes during an incident) rather than paging through every role update.

### 12. Verify a card you posted, and clean up your own stray posts

A post made by a script through the bot token cannot be verified from that script's stdout:
stdout is what the renderer INTENDED, and only Discord holds what it actually accepted. Read
the message back by id and print the embed skeleton, so the posted card can be diffed against
the render:

```bash
curl -s -H "Authorization: Bot $BOT_TOKEN" \
  "https://discord.com/api/v10/channels/{thread_id}/messages/{message_id}" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('MSG', d['id'], d['timestamp'], 'embeds=', len(d.get('embeds',[])))
for e in d.get('embeds',[]):
    print('==', e.get('title'), '|', (e.get('footer') or {}).get('text'))
    for f in e.get('fields',[]): print('  ['+f['name']+']', f['value'])
"
```

- **Two card DESIGNS can share one thread — tell them apart by embed title**, never by
  recency. A superseded design keeps being produced by whichever job still renders it, and
  the title is the one field that survives a redesign that changes every number. Grep the
  repo for the title string to find the producer before blaming the current one.
- **Only the current card belongs in an archive thread.** A stale or test card beside it makes
  the archive contradict itself, and the next reader cannot tell which one is live.
- **A bot can delete its OWN message with just its token** — no `MANAGE_MESSAGES`, no
  permission overwrite in play: `DELETE /channels/{thread}/messages/{id}` → `204` (`50013`
  means it is not its own message, so this is not a general moderation path). Deletion is
  irreversible and the body is gone from Discord, so it must remain reproducible from the repo
  if anyone needs to see it again; state which ids you removed and why.
- **"Delete your own posts in this thread" means filter by `author.id` == your bot's own
  `GET /users/@me` id, and delete nothing else.** A webhook post carries the WEBHOOK's user
  id (and an app post carries the application's), so an author-id filter preserves every
  other pipeline's messages, the operator's own messages, and other bots' — an owner-scoped
  purge, not a moderation sweep. Never key the filter on recency, embed shape, or channel:
  several pipelines post into one thread.
- **When the thread is meant to carry only a signal class, the purge must preserve the
  signals and drop the noise — decide per MESSAGE, then re-read the thread.** Compute the
  keep/delete sets from message content (a real incident vs a baseline/status card, a
  duplicate vs the survivor card) before issuing a single delete, then verify by re-fetching
  each thread and reporting what remains. A bulk delete verified only by its own 204 is a
  claim, not a state.

## Pitfalls

- **Discord 403s on the User-Agent, in both directions.** A `urllib.request` call with no `User-Agent` returns `403 Forbidden` on endpoints that answer fine to `curl` with the same token, and a POST carrying a *browser* UA (`Mozilla/5.0 ...`) is rejected with `403 code 40333 "internal network error"` — verified side by side on the same channel and token. Send a custom application UA on every write — Discord's own documented form `DiscordBot (<name>, <version>)` or a project UA (`FudCourtNews/1.0 (+https://fudcourt.my.id)`). **The same trap catches Node:** `fetch()` sends undici's default UA and is refused with `403 code 40333 "internal network error"` while `curl` at the SAME endpoint with the SAME token returns `200` — curl sends a UA, undici does not. Put `"user-agent": "DiscordBot (<name>, <version>)"` in the headers object of EVERY Node write path; a headers object carrying only `authorization` is the exact shape that fails, and because the curl probe passes you will blame the token before the UA. Never read either 403 as a permissions or membership problem.
- **`message_count: 0` does not mean the thread is empty.** A forum post reports 0
  while its starter message exists holding an attachment. Fetch
  `/channels/{thread_id}/messages` before calling a thread blank.
- **An idempotence guard keyed on "this thread already has a message" is ALWAYS true
  for a forum thread.** Every forum post (`type` 11) owns a starter message, so a pre-write
  check that returns on the first message skips EVERY thread, reports success, and writes
  nothing — a silent no-op indistinguishable from "already done", and it exits 0 so the
  scheduler stays green over an empty thread. Key the guard to your OWN marker instead:
  scan the last ~10 messages for a **bot-authored** message whose embed title carries a
  known string, and treat "marker absent" as "not yet posted".
- **`mentionable: false` on an opt-in role is a silent notifier killer.** An
  Administrator bot bypasses it, so a successful send from an admin bot proves nothing
  about whether a webhook or a non-admin bot can ping the role.
- **Role names and destination names drift apart — check them together.** A member
  subscribes by role and receives into a thread; if the role says `perp ring` and the
  thread says `Future Play`, the subscription does not name the same instrument.
  Report the mismatch instead of silently picking one spelling.

- **Never report "channel not found" from a single 403.** Run the control test from
  step 3 first; `50001` and `10003` mean opposite things.
- **A bot with Administrator that still gets `50001` is not in that guild.** Admin
  bypasses permission overwrites but not guild membership.
- **`systemctl cat <unit>` fails for these services — they are user units.** Use
  `systemctl --user cat <unit>` and `systemctl --user list-units --all`. A system
  unit and a user unit can share a name, and only the user one exists here.
- **Grep the repo for the channel ID before assuming it is configured.** If the ID
  appears nowhere in the codebase, it is a manually created channel, and changing it
  is a dashboard action rather than a code change.
- **Searching all of `~/.hermes/` for a numeric ID is slow and times out.** Narrow
  with `search_files` and a file_glob, or go straight to `~/.hermes/logs/agent.log`
  where the inbound message is logged with its platform.
- **Budget an embed's description inside the renderer — Discord rejects the WHOLE
  edit once it passes 4096.** The failure is shapeshift's setDescription union:
  sub-errors "Expected values to be equals" + "Invalid string length". A card that
  renders one line per ledger row edits fine for months and then fails EVERY
  refresh quietly once the ledger crosses the cap, leaving the live card
  permanently stale while the scheduler keeps ticking. Cap the render near 4050
  chars and append an overflow notice pointing at the full list, and assert the
  rendered description length in the card's dry-run output so the breach is caught
  before it blocks edits.
- **On any Discord API failure, log sub-errors and stack — never only
  `.message`.** discord.js wraps real causes in
  `AggregateError("Received one or more errors")`, whose `err.errors[]` carries the
  actual REST complaint; a catch that prints only `.message` turns a one-line fix
  into an undiagnosable night. In every catch around embed/REST work, iterate
  `err.errors[]` and print the first stack frames.
- **Bulk message purge has mechanics the single-delete path does not**:
  `POST /channels/{id}/messages/bulk-delete` takes max 100 ids per request and only
  messages <14 days old (older ones need individual
  `DELETE /channels/{id}/messages/{mid}`), a 204 answers with an EMPTY body that a
  JSON parser reads as failure, and rate limits arrive as `{"retry_after": N}` —
  sleep it and retry the same chunk. Snowflake → unix is
  `(id >> 22) // 1000 + 1420070400`. The dedupe-safe grouping rules (URL-identical
  pairs are safe at any age; same FULL normalized title only inside the incident
  window; keep the oldest; never truncate the title key) and the full recipe live
  in `fudcourt-development` → `references/feeds-pipeline.md`.

## Writing — always confirm first

Posting a message or creating a thread is a state-changing write to a live community
server visible to real members. Read everything, then **ask before the first write**.
A probe POST to test permissions is still a write if it succeeds; prefer deriving
permissions from `permission_overwrites` + member roles instead of sending a test
message.

## References

- `references/api-reference.md` — endpoint list, error codes, channel types, and
  permission bit values in one table.
- `references/optin-role-audit.md` — full read-only recipe for auditing opt-in roles,
  subscriber counts, overwrite wiring, forum threads, and code wiring.

For building (not inspecting) — gateway session/identify/resume rules, interaction
callbacks, components v2, OAuth2 flows, voice UDP handshake, and monetization — load
the `discord-platform-api` skill instead. This skill stays read-only forensics.
