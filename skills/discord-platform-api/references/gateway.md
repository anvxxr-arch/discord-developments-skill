# Gateway

Source: `events/gateway.md`, `events/gateway-events.md`.

## Endpoints

```
GET /gateway          # no auth; returns {"url": "wss://gateway.discord.gg/"}
GET /gateway/bot      # auth required; adds shards + session_start_limit
```

Cache the `url` from `GET /gateway`; only refetch when you cannot connect.
`GET /gateway/bot` should **not** be cached long — it changes as guilds are
joined/left.

Connect with explicit params: `wss://gateway.discord.gg/?v=10&encoding=json`.

| Param | Values |
|---|---|
| `v` | API version integer |
| `encoding` | `json` or `etf` |
| `compress` | `zlib-stream` or `zstd-stream` |

`encoding=json` recommended unless you specifically want ETF.

## Handshake Order

1. Connect → receive `op 10 Hello` with `heartbeat_interval` (ms).
2. Wait `heartbeat_interval * jitter` (jitter = random 0..1), send `op 1 Heartbeat`.
3. Continue `op 1` every `heartbeat_interval` ms, carrying last received `s` in `d`
   (`null` if none yet).
4. Send `op 2 Identify` with `token`, `intents`, `properties`.
5. Receive `READY` (a `op 0 Dispatch`). Cache `session_id` + `resume_gateway_url`.

Minimal identify:

```json
{"op": 2, "d": {"token": "...", "intents": 513,
  "properties": {"os": "linux", "browser": "my_library", "device": "my_library"}}}
```

`op 1` always answered with `op 11 Heartbeat ACK`.

## Zombied Connections

If no ACK arrives between heartbeat attempts, the connection is dead. Close with
any code **other than 1000 or 1001**, then reconnect and Resume. Do not silently
keep heartbeating.

## Disconnect Semantics

- Closing with `1000`/`1001` invalidates the session; the bot appears offline.
- Closing the TCP connection or using another code keeps the session alive for a
  few minutes — that is what makes Resume possible.
- `op 7 Reconnect` → resume immediately.
- `op 9 Invalid Session` with `d: true` → resume. With `d: false` (the common case)
  → disconnect, reconnect to the cached URL, and re-Identify.

## Resuming

Needs three values: `session_id`, `resume_gateway_url` (from READY), and the last
`s` from a Dispatch.

```json
{"op": 6, "d": {"token": "...", "session_id": "session_id_i_stored", "seq": 1337}}
```

- Connect to `resume_gateway_url` with the **same** `v` and `encoding` as the
  original connection. Not doing so causes a higher disconnect rate.
- Do **not** re-Identify before resuming.
- Missed events replay in order, ending with `RESUMED`.
- Resume does not count against the 1000/day Identify budget.

## Identify Limit

**1000 IDENTIFY calls per 24h, global across all shards.** Hitting it terminates
all sessions, **resets the bot token**, and emails the owner. This is the single
most expensive mistake in gateway code — always resume first, identify last.

## Intents

Bitwise values in `intents`. Each gates a set of related events; an event whose
intent is absent is silently never delivered. Required as of v8 (optional on v6).

| Intent | Bit |
|---|---|
| `GUILDS` | `1 << 0` |
| `GUILD_MEMBERS` (privileged) | `1 << 1` |
| `GUILD_MESSAGES` | `1 << 9` |
| `MESSAGE_CONTENT` (privileged) | `1 << 15` |

- `GUILD_PRESENCES` and `GUILD_MEMBERS` are **off by default on all API versions**
  regardless of version; enable in the Developer Portal and be approved if the app
  is eligible for verification.
- `MESSAGE_CONTENT` maps to no individual event; it controls whether content
  fields are populated on events that carry messages.
- Privileged intents also gate HTTP endpoints — `GET /guilds/{id}/members`
  requires `GUILD_MEMBERS`.
- `GUILD_MEMBER_UPDATE` for the current user is sent regardless of the intent.

## Sharding

Send `shard: [shard_id, num_shards]` in the Identify payload.

- Each shard supports at most **2500 guilds**; apps in 2500+ guilds **must** shard.
- Routing formula: `shard_id = (guild_id >> 22) % num_shards`
- `GET /gateway/bot` returns a recommended `shards` count.
- `num_shards` is routing only — it does not cap total sessions. Multiple sessions
  may share the same `[shard_id, num_shards]`, enabling zero-downtime handoff
  between deployments with different `num_shards`.

## Session Start Limit

```json
{"total": 1000, "remaining": 999, "reset_after": 14400000, "max_concurrency": 1}
```

`reset_after` is in **milliseconds**. `max_concurrency` = IDENTIFYs allowed per
5 seconds.

## Compression

- **Payload compression** (`compress=zlib-stream`) — JSON encoding only.
- **Transport compression** (`zstd-stream`) — works with either encoding.
- ETF is binary and has quirks; JSON is the safe default.

## State Tracking

Most state arrives in `READY` and subsequent `GUILD_CREATE`. Cache what the app
needs, update from events, and avoid re-fetching. `MESSAGE_CREATE` already embeds
the full member object, so caching members for permission purposes is often
unnecessary.

Guilds start **unavailable**; the gateway reconnects on your behalf and emits
`GUILD_CREATE` as they become available. Do not treat initial absence as a failure.
