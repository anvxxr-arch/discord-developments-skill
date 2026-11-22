# Channels and Threads

Source: `resources/channel.md`, `topics/threads.md`.

## Channel Types

| Type | Value | Notes |
|---|---|---|
| `GUILD_TEXT` | 0 | |
| `DM` | 1 | |
| `GUILD_VOICE` | 2 | |
| `GROUP_DM` | 3 | |
| `GUILD_CATEGORY` | 4 | container only |
| `GUILD_ANNOUNCEMENT` | 5 | crosspostable |
| `ANNOUNCEMENT_THREAD` | 10 | |
| `PUBLIC_THREAD` | 11 | |
| `PRIVATE_THREAD` | 12 | |
| `GUILD_STAGE_VOICE` | 13 | |
| `GUILD_DIRECTORY` | 14 | |
| `GUILD_FORUM` | 15 | |
| `GUILD_MEDIA` | 16 | |

Threads are channels — every channel endpoint accepts a thread id where it accepts a
channel id, with a few exceptions noted below.

## Channel Object — fields that matter

`id`, `type`, `guild_id`, `position`, `permission_overwrites`, `name`, `topic`
(≤ 1024), `nsfw`, `last_message_id`, `parent_id` (category or thread parent),
`rate_limit_per_user` (seconds, 0–21600), `owner_id` (threads), `thread_metadata`,
`message_count`, `member_count`, `default_auto_archive_duration` (minutes: 60, 1440,
4320, 10080), `flags`, `available_tags` (forums), `default_sort_order`,
`default_forum_layout`.

`rate_limit_per_user` on a thread is inherited from the parent at creation and can
only be changed with `MANAGE_THREADS`.

## Categories

`GUILD_CATEGORY` (4) has no messages. Its `permission_overwrites` are the template
for children — new channels created with `parent_id` set inherit a copy. Changing a
category's overwrites does **not** retroactively change children; you must sync
manually.

## Threads

### Creation

```
POST /channels/{channel.id}/threads
```

From an existing message:

```json
{"name": "thread name", "auto_archive_duration": 1440, "type": 11}
```

Without a message (public thread):

```json
{"name": "thread name", "auto_archive_duration": 1440, "type": 11, "invitable": true}
```

Private thread: `type: 12`, requires `CREATE_PRIVATE_THREADS`, and `invitable`
defaults true.

Limits: `name` ≤ 100 chars. `auto_archive_duration` in minutes, one of
**60, 1440, 4320, 10080**.

A thread is created **active** and its creator is added as a member.

### Forum / Media channels

`POST /channels/{id}/threads` on a `GUILD_FORUM` (15) or `GUILD_MEDIA` (16) channel
creates the thread **and** its starter message in one call:

```json
{"name": "post title", "message": {"content": "body", "embeds": [...],
 "allowed_mentions": {...}, "components": [...], "sticker_ids": [...],
 "attachments": [...], "flags": 0}, "applied_tags": ["tag_id"]}
```

You **cannot** `POST /channels/{forum_id}/messages` directly — that returns
`50008` (cannot send messages in a non-text channel). Forum posts must go through the
threads endpoint.

`applied_tags` max 5, ids from `available_tags`.

### Lifecycle

| Action | Endpoint |
|---|---|
| Join | `PUT /channels/{channel.id}/thread-members/@me` |
| Leave | `DELETE /channels/{channel.id}/thread-members/@me` |
| Add member | `PUT /channels/{channel.id}/thread-members/{user.id}` |
| Remove member | `DELETE /channels/{channel.id}/thread-members/{user.id}` |
| Get members | `GET /channels/{channel.id}/thread-members` |
| Archive | `PATCH /channels/{channel.id}` with `{"archived": true, "locked": false}` |
| Unarchive | `PATCH ... {"archived": false}` |
| List active | `GET /channels/{channel.id}/threads/active` |
| List public archived | `GET /channels/{channel.id}/threads/archived/public` |
| List private archived | `GET /channels/{channel.id}/threads/archived/private` |
| List joined private | `GET /channels/{channel.id}/users/@me/threads/archived/private` |

- Threads auto-archive after `auto_archive_duration` of inactivity. Any message or
  member action resets the timer.
- Archived threads are read-only until unarchived. `locked: true` prevents
  unarchiving by anyone without `MANAGE_THREADS`.
- Unarchiving requires `SEND_MESSAGES_IN_THREADS` (and `MANAGE_THREADS` if locked).
- `GET /channels/{id}/threads/archived/public` is paginated with `before` and
  `limit`, and only works on `GUILD_TEXT`/`GUILD_ANNOUNCEMENT` — not on forums.

### Thread-only permissions

| Permission | Bit |
|---|---|
| `MANAGE_THREADS` | `1 << 34` |
| `CREATE_PUBLIC_THREADS` | `1 << 35` |
| `CREATE_PRIVATE_THREADS` | `1 << 36` |
| `SEND_MESSAGES_IN_THREADS` | `1 << 38` |

`SEND_MESSAGES` (`1 << 11`) is **not** used in threads. A member with
`SEND_MESSAGES` but without `SEND_MESSAGES_IN_THREADS` can post in the parent channel
and not in its threads.

## Crossposting (announcement channels)

`POST /channels/{channel.id}/messages/{message.id}/crosspost` — requires the channel
to be `GUILD_ANNOUNCEMENT` and the message to carry neither `CROSSPOSTED` nor
`IS_CROSSPOST`. Returns the crossposted message. `SUPPRESS_EMBEDS` is not allowed on
crossposted messages.

## Sanity Checks

- `GET /channels/{id}` on a thread works but returns the thread shape — check `type`
  before treating it as a text channel.
- `parent_id` on a thread points at the parent channel; on a channel it points at
  the category. Same field, two meanings.
- Deleting a thread deletes the messages in it. Deleting a forum post deletes the
  thread.
