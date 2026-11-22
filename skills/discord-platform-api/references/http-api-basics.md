# HTTP API Basics

Source: `reference.md` (Discord API Reference).

## Versioning

Base path: `https://discord.com/api/v{version_number}`. Omitting the version routes
to the current default.

| Version | Status |
|---|---|
| 10 | Available (default) |
| 9 | Available |
| 8 | Deprecated |
| 7 | Deprecated |
| 6 | Deprecated |
| 5 and below | Discontinued |

## Authentication

Three ways, all via the `Authorization` header:

1. Bot token — `Authorization: Bot MTk4Nj...kKWs`
2. OAuth2 bearer — `Authorization: Bearer CZhtkL...kChw`
3. Basic — `Authorization: Basic MTk4Nj...Nm96`, i.e. base64 of
   `client_id:client_secret`. **Token endpoints only.**

## User-Agent

Required format: `DiscordBot ($url, $versionNumber)`.

This is not cosmetic. A missing UA or a browser UA (`Mozilla/5.0 ...`) is refused
with `403 code 40333 "internal network error"` on endpoints that answer `200` to
`curl` with the same token. Node `fetch()` (undici default UA) hits this while
`curl` passes — always set `user-agent` explicitly in write paths.

## TLS

All HTTP-layer and WebSocket services use TLS 1.2.

## Snowflakes

64-bit IDs, always returned as **strings** in the HTTP API to avoid integer
overflow. Discord epoch = `1420070400000` (first second of 2015).

| Field | Bits | Retrieval |
|---|---|---|
| Timestamp (ms since epoch) | 63–22 (42 bits) | `(snowflake >> 22) + 1420070400000` |
| Internal worker ID | 21–17 (5 bits) | `(snowflake & 0x3E0000) >> 17` |
| Internal process ID | 16–12 (5 bits) | `(snowflake & 0x1F000) >> 12` |
| Increment | 11–0 (12 bits) | `snowflake & 0xFFF` |

Generate a snowflake for a timestamp: `(timestamp_ms - 1420070400000) << 22`.

IDs echoed back as **integers** happen only when the request sent a non-bigint
value in an `id` field (e.g. `GUILD_MEMBERS_CHUNK` with `user_ids: [123123]`).
Never happens for IDs originating from Discord.

## Pagination

Standard pattern: `before` / `after` snowflake params combined with `limit`.
Generate a boundary snowflake from a timestamp rather than paging blindly.

## Error Format (v8+)

```json
{"code": 50035, "message": "Invalid Form Body",
 "errors": {"access_token": {"_errors": [{"code": "BASE_TYPE_REQUIRED", "message": "This field is required"}]}}}
```

Nested keys index into arrays (`"0"`, `"1"`); `_errors` holds the leaf list. Parse
`errors` recursively to find the offending key — printing only `message` gives you
"Invalid Form Body" and nothing actionable.

## Nullable vs Optional

Field-name suffix `?` = optional (may be absent). Type prefix `?` = nullable (may
be `null`). `optional_and_nullable_field?` with type `?string` is both.

## Consistency

Discord is eventually consistent. Events may never arrive, arrive once, or arrive
up to N times. Client actions are not serialized and may execute in any order.
Design handlers to be idempotent; do not treat event order as a guarantee.

## Uploading Files

- `multipart/form-data` body. Non-file params either as individual form fields or
  as one JSON blob in `payload_json`.
- File fields are `files[n]` — `files[0]`, `files[1]`, `files[42]`. Each needs a
  `Content-Disposition` subpart header with `filename` and a unique `name`.
- Index `n` is a snowflake placeholder usable in the `attachments` array, passed
  via `payload_json`.
- Images reference attachments in embeds via `attachment://filename`.
- Per-file limit: default **20 MiB**, higher with Nitro or Boost tier.
  Max request size for a message: **25 MiB**.
- Editing: on `PATCH`, only files listed in `attachments` survive — omitted files
  are removed. `description` and `is_spoiler` on existing attachments are editable.

## ISO8601

Timestamps are ISO8601, typed `ISO8601` in the tables. Not unix seconds.
