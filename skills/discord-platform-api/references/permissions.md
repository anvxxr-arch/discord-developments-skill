# Permissions and Roles

Source: `topics/permissions.md`, `resources/guild.md` (role object).

## Model

Permissions are a 64-bit integer bitfield. Three inputs combine:

1. `@everyone` role permissions (base for everyone in the guild)
2. Union of all roles the member holds (excluding `@everyone`, which is already included)
3. Channel permission overwrites (allow/deny per role and per member)

Administrator (`1 << 3`, value 8) bypasses **all** permission checks and all
overwrites, including channel overwrites and sync.

## Calculation

Guild-level for a member:

```
base = @everyone.permissions
for each role in member.roles (excluding @everyone):
    base |= role.permissions
```

Channel-level is where order matters. Sort overwrites: `@everyone` first, then role
overwrites by ascending role position, then the member overwrite last.

```
permissions = base
for each overwrite in sorted(overwrites):
    permissions &= ~overwrite.deny
    permissions |= overwrite.allow
```

Then apply Guild-level implicit gates: `VIEW_CHANNEL` needed to see the channel at
all, and a channel cannot grant a permission the guild level denies for certain
non-content permissions.

If the result has `ADMINISTRATOR`, treat all permissions as granted. This is the
single most common source of "why does my bot 403 when the math says it should
work" — resolve the effective permission including Administrator before blaming the
channel overwrites.

## Common Bit Values

| Permission | Bit |
|---|---|
| `CREATE_INSTANT_INVITE` | `1 << 0` |
| `KICK_MEMBERS` | `1 << 1` |
| `BAN_MEMBERS` | `1 << 2` |
| `ADMINISTRATOR` | `1 << 3` |
| `MANAGE_CHANNELS` | `1 << 4` |
| `MANAGE_GUILD` | `1 << 5` |
| `ADD_REACTIONS` | `1 << 6` |
| `VIEW_AUDIT_LOG` | `1 << 7` |
| `PRIORITY_SPEAKER` | `1 << 8` |
| `STREAM` | `1 << 9` |
| `VIEW_CHANNEL` | `1 << 10` |
| `SEND_MESSAGES` | `1 << 11` |
| `MANAGE_MESSAGES` | `1 << 13` |
| `EMBED_LINKS` | `1 << 14` |
| `ATTACH_FILES` | `1 << 15` |
| `READ_MESSAGE_HISTORY` | `1 << 16` |
| `MENTION_EVERYONE` | `1 << 17` |
| `USE_EXTERNAL_EMOJIS` | `1 << 18` |
| `CONNECT` | `1 << 20` |
| `SPEAK` | `1 << 21` |
| `MUTE_MEMBERS` | `1 << 22` |
| `DEAFEN_MEMBERS` | `1 << 23` |
| `MOVE_MEMBERS` | `1 << 24` |
| `MANAGE_NICKNAMES` | `1 << 27` |
| `MANAGE_ROLES` | `1 << 28` |
| `MANAGE_WEBHOOKS` | `1 << 29` |
| `MANAGE_GUILD_EXPRESSIONS` | `1 << 30` |
| `USE_APPLICATION_COMMANDS` | `1 << 31` |
| `MANAGE_EVENTS` | `1 << 33` |
| `MANAGE_THREADS` | `1 << 34` |
| `CREATE_PUBLIC_THREADS` | `1 << 35` |
| `CREATE_PRIVATE_THREADS` | `1 << 36` |
| `SEND_MESSAGES_IN_THREADS` | `1 << 38` |
| `USE_EMBEDDED_ACTIVITIES` | `1 << 39` |
| `MODERATE_MEMBERS` | `1 << 40` |
| `VIEW_CREATOR_MONETIZATION_ANALYTICS` | `1 << 41` |
| `USE_SOUNDBOARD` | `1 << 42` |
| `CREATE_GUILD_EXPRESSIONS` | `1 << 43` |
| `CREATE_EVENTS` | `1 << 44` |
| `SEND_VOICE_MESSAGES` | `1 << 46` |
| `SEND_POLLS` | `1 << 49` |

## Traps

- **`SEND_MESSAGES` does not imply `SEND_MESSAGES_IN_THREADS`.** Threads use the
  thread-specific bits (`1 << 38`), plus `CREATE_PUBLIC_THREADS` /
  `CREATE_PRIVATE_THREADS` for starting them. `MANAGE_THREADS` lets you act on any
  thread but does not let you post in one you cannot send to.
- **`VIEW_CHANNEL` denial wins over everything at channel level** except
  `ADMINISTRATOR`. If a channel denies `VIEW_CHANNEL` for a role, everything else on
  that channel is moot.
- **`ADMINISTRATOR` cannot be granted through a channel overwrite.** It is a role
  permission; channel overwrites for it may appear to work only because a role grants
  it.
- **`MANAGE_ROLES` cannot grant or revoke permissions the actor doesn't hold**, and
  role position matters: you can only manage roles below your highest role.
- **`MENTION_EVERYONE`** is required to ping `@everyone`/`@here` even when
  `allowed_mentions` permits it. Both gates apply.
- **Bot permissions in a channel** also depend on the bot's own role position
  relative to the target — a bot with `MANAGE_ROLES` cannot edit a role above its own
  highest role.

## Role Objects

`GET /guilds/{guild.id}/roles` returns an array (it is not paginated).

| Field | Meaning |
|---|---|
| `id` | role id |
| `name` | |
| `color` | int; 0 = default |
| `colors` | gradient object (primary/secondary/tertiary) |
| `hoist` | shown separately in member list |
| `position` | higher = stronger; `0` is always `@everyone` |
| `permissions` | bitfield string |
| `managed` | true = bot/integration role, cannot be deleted |
| `mentionable` | |
| `flags` | role flag bitfield |

`@everyone` role id equals the guild id.

## Channel Overwrites

`permission_overwrites` on a channel: `[{id, type, allow, deny}]` where `type` is
`0` (role) or `1` (member). `allow`/`deny` are permission bitfields serialized as
strings.

To grant one permission without disturbing the rest, send the full intended
`allow`/`deny` — `PUT /channels/{id}/permissions/{overwrite_id}` replaces, it does
not merge.

Overwrites are synced per channel by copying the parent category's overwrites onto
the child channel. There is no bulk sync endpoint; do it client-side.

## Verifying Effective Permissions

There is no endpoint that returns "can this member do X". Compute it, or use the
behavioural probe: attempt the action and read the error code. `50013 Missing
Permissions` means permissions; `50001 Missing Access` means the bot cannot see the
channel at all.
