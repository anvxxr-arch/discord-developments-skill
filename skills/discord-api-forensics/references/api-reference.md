# Discord REST API v10 — quick reference

Base: `https://discord.com/api/v10`
Auth header: `Authorization: Bot <token>`

## Snowflake

```
creation_ms = (id >> 22) + 1420070400000
```

17–20 decimal digits. Higher bits are a timestamp, so sorting IDs sorts by creation.

## Error codes that matter

| code | message | means |
|---|---|---|
| 10003 | Unknown Channel | ID is not a channel (or not one this bot can ever see) |
| 10004 | Unknown Guild | ID is not a guild |
| 10013 | Unknown User | ID is not a user |
| 50001 | Missing Access | object EXISTS, bot lacks permission |
| 50008 | Cannot send messages in a non-text channel | target is a forum/voice/other non-text channel |
| 50035 | Invalid Form Body | malformed payload |
| 40001 | Unauthorized | bad/absent token |

`50001` vs `10003` is the existence signal. Always pair the target request with a
known-fake ID so the two codes are directly comparable.

## Endpoints

| Purpose | Method + path |
|---|---|
| Bot identity | `GET /users/@me` |
| Bot's guilds | `GET /users/@me/guilds` |
| Bot's DM channels | `GET /users/@me/channels` |
| Channel object | `GET /channels/{id}` |
| Channel messages | `GET /channels/{id}/messages?limit=N` |
| Create message | `POST /channels/{id}/messages` |
| Channel webhooks | `GET /channels/{id}/webhooks` |
| Guild channels | `GET /guilds/{gid}/channels` |
| Guild roles | `GET /guilds/{gid}/roles` |
| Guild member | `GET /guilds/{gid}/members/{uid}` |
| Guild object | `GET /guilds/{gid}` |
| Active threads | `GET /guilds/{gid}/threads/active` |
| Archived threads | `GET /channels/{forum_id}/threads/archived/public?limit=N` |
| Create forum post | `POST /channels/{forum_id}/threads` |
| Create thread in text | `POST /channels/{id}/threads` |

## Channel types

| type | kind |
|---|---|
| 0 | text |
| 2 | voice |
| 4 | category |
| 5 | announcement |
| 13 | stage |
| 15 | forum |

Only type 0 and 5 accept `POST /channels/{id}/messages`. Type 15 requires the
`/threads` endpoint.

## Permission bits (decimal value)

| bit | name | value |
|---|---|---|
| 0 | CREATE_INSTANT_INVITE | 1 |
| 1 | KICK_MEMBERS | 2 |
| 2 | BAN_MEMBERS | 4 |
| 3 | ADMINISTRATOR | 8 |
| 4 | MANAGE_CHANNELS | 16 |
| 5 | MANAGE_GUILD | 32 |
| 10 | VIEW_CHANNEL | 1024 |
| 11 | SEND_MESSAGES | 2048 |
| 13 | MANAGE_MESSAGES | 8192 |
| 14 | EMBED_LINKS | 16384 |
| 15 | ATTACH_FILES | 32768 |
| 16 | READ_MESSAGE_HISTORY | 65536 |
| 17 | MENTION_EVERYONE | 131072 |
| 20 | CONNECT | 1048576 |
| 34 | MANAGE_THREADS | 17179869184 |
| 35 | CREATE_PUBLIC_THREADS | 34359738368 |
| 36 | CREATE_PRIVATE_THREADS | 68719476736 |
| 38 | SEND_MESSAGES_IN_THREADS | 274877906944 |

Decode a mask:

```python
v = 8864258448162815
[1 << i for i in range(64) if v >> i & 1]
```

Note `1049600 = VIEW_CHANNEL + CONNECT` — a deny of that value hides a channel from
that role entirely.

## Bot invite URL

```
https://discord.com/api/oauth2/authorize?client_id=<APP_ID>&scope=bot%20applications.commands&permissions=<MASK>
```

Minimum useful mask for reading and posting in a **text channel**: `68672`
= VIEW_CHANNEL 1024 + SEND_MESSAGES 2048 + READ_MESSAGE_HISTORY 65536 +
ADD_REACTIONS 64 (decoded: bits 6, 10, 11, 16 — it does **not** include EMBED_LINKS).

Add `16384` (EMBED_LINKS) and `32768` (ATTACH_FILES) to send rich cards or files.

**Posting in threads needs thread bits, not `SEND_MESSAGES`.** Union in
`34359738368` (CREATE_PUBLIC_THREADS) and `274877906944` (SEND_MESSAGES_IN_THREADS).
Full forum + thread posting mask, verified by decoding: `309237763072`
= 1024 + 2048 + 65536 + 16384 + 32768 + 34359738368 + 274877906944.
