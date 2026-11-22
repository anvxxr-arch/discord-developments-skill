# Messages and Components

Source: `resources/message.md`, `components/reference.md`.

## Message Object — hard limits

| Field | Limit |
|---|---|
| `content` | 2000 chars |
| `embeds` | 10 per message |
| `attachments` | 10 per message |
| filesize | 25 MiB per request (25 * 1024 * 1024) |
| `components` | 40 total; 5 rows for plain messages |
| poll `answers` | 10 |

`content` has no per-message floor, but **a message needs `content`, `embeds`,
`components`, `file`, or `poll`** — all empty is a 400.

## Embed Budget — two limits at once

| Part | Limit |
|---|---|
| title | 256 |
| description | 4096 |
| fields | 25 |
| field.name | 256 |
| field.value | 1024 |
| footer.text | 2048 |
| author.name | 256 |
| **sum of all chars in all embeds** | **6000** |

The 6000 total is the one people miss. Exceeding either the per-field limits or the
sum rejects the entire request with 400 — you cannot send a partial embed.

## allowed_mentions

Always set it when user-supplied text reaches `content`. Defaults silently allow
`@everyone`/`@here`, which is a self-inflicted mention raid.

```json
{"parse": ["users", "roles"], "roles": ["<role_id>"], "users": ["<user_id>"],
 "replied_user": false}
```

| Field | Type | Meaning |
|---|---|---|
| `parse` | array | `"roles"`, `"users"`, `"everyone"` |
| `roles` | snowflakes | up to 100; overrides `parse` for roles |
| `users` | snowflakes | up to 100; overrides `parse` for users |
| `replied_user` | bool | mention the replied-to user (default true on replies) |

`{"parse": []}` disables all mentions. `replied_user: false` on replies prevents the
reply from pinging.

## Message Flags

| Flag | Value |
|---|---|
| `CROSSPOSTED` | `1 << 0` |
| `IS_CROSSPOST` | `1 << 1` |
| `SUPPRESS_EMBEDS` | `1 << 2` |
| `SOURCE_MESSAGE_DELETED` | `1 << 3` |
| `URGENT` | `1 << 4` |
| `HAS_THREAD` | `1 << 5` |
| `EPHEMERAL` | `1 << 6` |
| `LOADING` | `1 << 7` |
| `FAILED_TO_MENTION_ROLES_IN_THREAD` | `1 << 8` |
| `SUPPRESS_NOTIFICATIONS` | `1 << 12` |
| `IS_VOICE_MESSAGE` | `1 << 13` |
| `IS_COMPONENTS_V2` | `1 << 15` |

`IS_COMPONENTS_V2` **forbids** `content`, `embeds`, and `poll` in the same message,
and **cannot be unset** once set.

`SUPPRESS_NOTIFICATIONS` (`1 << 12`) = silent message, no push notification.

## Message Types worth knowing

`0` DEFAULT, `19` REPLY, `20` CHAT_INPUT_COMMAND, `21` THREAD_STARTER_MESSAGE,
`46` POLL_RESULT. A bot can only create `0`, `19` (reply via `message_reference`),
and `20` (via interaction) — the rest are system-generated.

Reply: pass `message_reference: {"message_id": "...", "channel_id": "...", "guild_id": "...",
"fail_if_not_exists": true}`. Cross-channel replies require `channel_id` and only
work in guilds.

## Component Types

| Type | Value |
|---|---|
| ACTION_ROW | 1 |
| BUTTON | 2 |
| STRING_SELECT | 3 |
| TEXT_INPUT | 4 |
| USER_SELECT | 5 |
| ROLE_SELECT | 6 |
| MENTIONABLE_SELECT | 7 |
| CHANNEL_SELECT | 8 |
| SECTION | 9 |
| TEXT_DISPLAY | 10 |
| THUMBNAIL | 11 |
| MEDIA_GALLERY | 12 |
| FILE | 13 |
| SEPARATOR | 14 |
| CONTAINER | 15 |

## Components V1 vs V2

**V1** (no flag): `content` + `embeds` + up to 5 `ACTION_ROW`s. Classic layout.

**V2** (`IS_COMPONENTS_V2`): `components` only, no `content`/`embeds`/`poll`.
Top level may contain `CONTAINER`, `SECTION`, `TEXT_DISPLAY`, `MEDIA_GALLERY`,
`SEPARATOR`, `ACTION_ROW`, `FILE`. This is the layout for rich modular cards.

Buttons live inside `ACTION_ROW` in both. An `ACTION_ROW` takes at most **5** buttons
or **1** select.

## Button Constraints

- `label` ≤ 80 chars; `custom_id` ≤ 100; `url` ≤ 512.
- Button styles: `1` PRIMARY, `2` SECONDARY, `3` SUCCESS, `4` DANGER, `5` LINK,
  `6` PREMIUM.
- `custom_id` required unless style is `5` (link) or `6` (premium).
- `url` required for style `5`; `sku_id` required for style `6`.
- `emoji` and `label` cannot both be omitted on a non-link button.
- `disabled` stops interactions but the button still renders.

## Selects

`SELECT` components take `options` (≤ 25), each `{label, value, description?, emoji?,
default?}`. `STRING_SELECT` needs `custom_id`; other selects need `custom_id` too but
ignore `options`. `min_values`/`max_values` default 1; `max_values` ≤ 25.

## Modals

`type: 9` callback with `data: {"custom_id", "title" (≤ 45), "components": [ACTION_ROW]}`.
Modals accept only `TEXT_INPUT` (type 4) in their first release line — not buttons
or selects. `TEXT_INPUT` styles: `1` SHORT (≤ 4000), `2` PARAGRAPH.

Modal submit arrives as interaction type `5` with `data.custom_id` matching.

## Polls

`poll: {"question": {"text": "..."}, "answers": [{"poll_media": {"text": "..."}}],
"duration": 24, "allow_multiselect": false, "layout_type": 1}`.
`question.text` ≤ 300, answer `poll_media.text` ≤ 55, `duration` in hours (1–768
default range), 2–10 answers.

## Anti-patterns

- Building embeds without counting the 6000-char sum → late 400s on long content.
- `content: ""` with components only **and** setting V2 flag — V2 forbids `content`
  entirely for some paths; omit the key rather than sending empty string.
- Reusing `custom_id` across different components in one message — handlers cannot
  disambiguate.
- Assuming `EPHEMERAL` works on regular `POST /channels/{id}/messages` — it is an
  interaction/webhook flag only.
