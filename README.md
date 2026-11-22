# discord-developments-skill

Agent skill pack for the **Discord Developer Platform** — distilled from
`https://docs.discord.com/developers/` into two loadable skills: one for *building*
against the API, one for *inspecting* a live guild.

Not a client library, not a tutorial, no wrapper code. Plain HTTP + WebSocket facts
with the exact limits, bitfields, and error codes that decide whether a request works.
Written for Hermes Agent (`skill_view`), but the `SKILL.md` + `references/` layout
works with any agent that reads markdown skills.

---

## What's Inside

| Skill | Purpose | Files |
|---|---|---|
| `discord-platform-api` | Build bots, interactions, webhooks, gateway clients | 1 SKILL.md + 13 references |
| `discord-api-forensics` | Resolve IDs, diagnose 403s, audit guilds read-only | 1 SKILL.md + 2 references |

**2,494 lines total.** Zero reproduction of vendor docs — every chapter is synthesized.

---

## `discord-platform-api` — 13 chapters

| # | Reference | Covers |
|---|---|---|
| 1 | `http-api-basics.md` | versioning, 3 auth forms, User-Agent gate, snowflakes, pagination, multipart upload |
| 2 | `formatting-and-cdn.md` | mention/timestamp syntax, CDN paths, signed attachment URLs, file-type filters |
| 3 | `rate-limits.md` | bucket headers, 429 payloads, 50/s global, `shared` scope trap |
| 4 | `gateway.md` | Hello/heartbeat/Identify/Resume, intents, sharding, compression |
| 5 | `interactions.md` | callback types, 3s deadline, 15min token, Ed25519 endpoint security |
| 6 | `messages-and-components.md` | embed 6000-char budget, message flags, components v1 vs v2 |
| 7 | `permissions.md` | 64-bit bitfield, overwrite computation order, thread bits |
| 8 | `channels-and-threads.md` | all 17 channel types, forum posts, thread lifecycle |
| 9 | `webhooks.md` | execute webhook, `wait`, `thread_id`, forum `thread_name`, Slack/GitHub compat |
| 10 | `oauth2.md` | authorization code + PKCE, client credentials, `webhook.incoming` |
| 11 | `voice.md` | UDP discovery handshake, encryption modes, DAVE/E2EE, close codes |
| 12 | `monetization.md` | SKUs, entitlements vs subscriptions, premium buttons, test mode |
| 13 | `status-codes.md` | gateway opcodes, close codes, HTTP codes, JSON error codes |

## `discord-api-forensics` — read-only ops

| Reference | Covers |
|---|---|
| `api-reference.md` | endpoint list, error codes, channel types, permission bit values |
| `optin-role-audit.md` | full recipe: opt-in roles, subscriber counts, overwrite wiring, code wiring |

Forensics answers one class of question: *"what is this ID, does it exist, and can my bot see it."* It performs no writes until you explicitly approve one.

---

## Install

### Hermes Agent

```bash
git clone https://github.com/anvxxr-arch/discord-developments-skill.git
cp -r discord-developments-skill/skills/* ~/.hermes/skills/devops/
```

Then load on demand:

```python
skill_view(name="discord-platform-api")
skill_view(name="discord-platform-api", file_path="references/gateway.md")
```

### Other agents (Claude Code, Codex, Cursor)

```bash
./scripts/install.sh ~/.claude/skills
```

Each skill is self-contained: `SKILL.md` is the index, `references/*.md` are the chapters.

---

## The Facts Worth Knowing

These are the ones that cost hours when missed. All verified against live docs.

| Trap | Reality |
|---|---|
| `403` on a valid token | `code 40333 "internal network error"` = **User-Agent**, not auth. Node `fetch()` hits it; `curl` passes. |
| IDENTIFY budget | **1000 per 24h** across all shards → hitting it **resets your bot token** |
| Embed size | Not just `description ≤ 4096` — a **6000-char sum across all embeds** also applies |
| Posting in threads | `SEND_MESSAGES` does nothing. Needs `SEND_MESSAGES_IN_THREADS` (`1 << 38`) |
| Forum channel POST | `50008 Cannot send messages in a non-text channel` — must go through `/threads` with a starter `message` |
| `IS_COMPONENTS_V2` | Forbids `content`/`embeds`/`poll`, and **cannot be unset** once set |
| `50001` vs `10003` | `Missing Access` (exists, no permission) vs `Unknown Channel` (does not exist) |
| Interaction response | **3 seconds** or the token dies. Token stays valid **15 minutes** after |
| Resume vs Identify | Resume does not count against the 1000/day budget — always resume first |
| Webhook `wait` | Without `wait=true` you get `204` and no message id, so you can't edit what you sent |

---

## Verification

The one command that proves your token, User-Agent, and API version are all correct:

```bash
curl -s -H "Authorization: Bot $TOKEN" \
     -H "User-Agent: DiscordBot (probe, 1.0)" \
     https://discord.com/api/v10/users/@me
```

A JSON user object with `bot: true` = all three are right.
`401` = token. `403 code 40333` = User-Agent.

---

## Structure

```
discord-developments-skill/
├── README.md
├── LICENSE
├── .gitignore
├── scripts/
│   └── install.sh
└── skills/
    ├── discord-platform-api/
    │   ├── SKILL.md              # index: when to use, procedure, pitfalls, chapter map
    │   └── references/           # 13 chapters, load one at a time
    └── discord-api-forensics/
        ├── SKILL.md
        └── references/
```

Each `SKILL.md` follows the Hermes section order: intro → When to Use →
Prerequisites → How to Run → Quick Reference → Procedure → Pitfalls → Verification →
References.

---

## Source & Scope

Derived from the official Discord developer documentation. Page index:
`https://docs.discord.com/llms.txt`. Every page is also served as markdown by
appending `.md` to its path.

**Not covered:** shard hosting/infrastructure, client library selection, app
verification/submission process, and Discord's internal non-public APIs.

Vendor docs change. When a detail here conflicts with live docs, the live docs win —
re-fetch the page rather than trusting a cached chapter.

---

## License

MIT — see [LICENSE](LICENSE).

Discord is a trademark of Discord Inc. This project is unofficial and not affiliated
with or endorsed by Discord Inc.
