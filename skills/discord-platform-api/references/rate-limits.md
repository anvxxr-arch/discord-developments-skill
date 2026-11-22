# Rate Limits

Source: `topics/rate-limits.md`.

## Core Rule

Never hardcode limits. Parse the response headers and react. Limits are per
individual bot/user (determined by the auth used) and exist both per-route and
globally.

## Per-Route Buckets

May include the HTTP method. Related endpoints can share a bucket — the
`X-RateLimit-Bucket` header is the canonical bucket identifier; key your local
limiter on it, not on the URL.

Top-level resource IDs are calculated independently: `channel_id`, `guild_id`,
and `webhook_id` (+ `webhook_token`). Exceeding `/channels/1234` does not affect
`/channels/9876`.

## Headers

```
X-RateLimit-Limit: 5
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1470173023          # epoch seconds
X-RateLimit-Reset-After: 1             # seconds, may be fractional
X-RateLimit-Bucket: abcd1234
```

Present only on 429:

- `X-RateLimit-Global` — set when the *global* limit was hit
- `X-RateLimit-Scope` — `user` | `global` | `shared`

## 429 Handling

Body: `{"message": "...", "retry_after": 64.57, "global": false, "code": <optional>}`.
Route headers are also sent. Sleep on `Retry-After` header or `retry_after` field,
then retry the same request. `X-RateLimit-Scope: shared` means a resource-level
limit — `retry_after` can be much larger than `Reset-After` (verified in docs:
`Retry-After: 1337` with `Reset-After: 64.57`). Trust `Retry-After`.

## Global Limit

**50 requests per second** for all bots. Unauthenticated requests are limited per
IP. Independent of per-route limits.

Symptom distinction worth knowing: being temporarily Cloudflare-banned at startup,
repeatedly, is usually **not** the global rate limit — it is an unhandled error
spike tripping the error threshold.

## Exceptions

Emoji-control routes do not follow normal conventions. They are limited
per-guild, so the returned quota can be inaccurate and you will see 429s anyway.

## Gateway Is Separate

Gateway rate limits are **not** these. Gateway: 120 events per connection per 60s
(avg 2/s); exceeding it disconnects immediately. Concurrent IDENTIFY is limited
per 5 seconds (`max_concurrency`), and hitting it returns `op 9 Invalid Session`.
