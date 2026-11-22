# Opt-in role / signal-distribution audit

Recipe for "check the roles" and "check the channel" asks on a server that
publishes signals into role-gated channels. Read-only throughout.

## 0. Load the token that can actually see the guild

```bash
set -a; . /home/dwizzy/.config/fudcourt/env 2>/dev/null; set +a
T="$FUDCOURT_BOT_TOKEN"; G=<guild_id>
```

Verify identity + guild membership before anything else — a bot that is not in the
guild returns `50001` for every object and looks like a permission bug.

```bash
curl -s -H "Authorization: Bot $T" https://discord.com/api/v10/users/@me
curl -s -H "Authorization: Bot $T" https://discord.com/api/v10/users/@me/guilds
```

## 1. Roles, with creation time

Creation time from the snowflake is what tells a rename from a creation:

```python
def created(rid):
    import datetime
    return datetime.datetime.fromtimestamp(
        ((int(rid) >> 22) + 1420070400000) / 1000, datetime.timezone.utc)
```

```bash
curl -s -H "Authorization: Bot $T" "https://discord.com/api/v10/guilds/$G/roles"
```

Print `id, position, color, mentionable, hoist, permissions, name, created`. Roles
created seconds apart belong to one batch and share a purpose — group them in the
report rather than listing 20 flat rows.

## 2. Subscriber census

```bash
curl -s -H "Authorization: Bot $T" "https://discord.com/api/v10/guilds/$G/members?limit=1000"
```

Invert the member list into `role_id -> [usernames]`. Any opt-in role with an empty
list notifies nobody, no matter how correct its wiring is. Also print the target
user's own role set — a user who built the role often has not assigned it to himself.

## 3. Overwrite scan across every channel

```bash
curl -s -H "Authorization: Bot $T" "https://discord.com/api/v10/guilds/$G/channels"
```

For each channel, resolve `permission_overwrites[].id` to a role name and print
`allow`/`deny`. A role id that appears in **zero** overwrites is cosmetic.

Decode the bitmasks when a deny blocks something:

```python
v = 1049600
[1 << i for i in range(64) if v >> i & 1]   # -> [10, 20] = VIEW_CHANNEL, CONNECT
```

Common values seen on this host:

| mask | meaning |
|---|---|
| `1024` | `VIEW_CHANNEL` |
| `1049600` | `VIEW_CHANNEL` + `CONNECT` |
| `2048` | `SEND_MESSAGES` |
| `65536` | `READ_MESSAGE_HISTORY` |
| `1099511627776` | `SEND_MESSAGES_IN_THREADS` |

A channel with `@everyone: deny 1049600` plus `Moderator: allow 1049600` is fully
private and moderator-only. That is a deliberate shape, not a misconfiguration.

## 4. Thread / post inventory per forum

```bash
curl -s -H "Authorization: Bot $T" "https://discord.com/api/v10/guilds/$G/threads/active"
curl -s -H "Authorization: Bot $T" "https://discord.com/api/v10/channels/$FORUM/threads/archived/public?limit=50"
```

Filter active threads by `parent_id == forum_id`. Then fetch each thread's messages:

```bash
curl -s -H "Authorization: Bot $T" "https://discord.com/api/v10/channels/$THREAD/messages?limit=10"
```

`message_count` is unreliable — a starter post reports `0` while existing. Read
`content`, `attachments[]`, and `embeds[]`; attachment-only posts have `content: ""`.

## 5. Code wiring

```bash
grep -rn "<role_id>\|<thread_id>\|<role name>" --include="*.go" --include="*.ts" \
  --include="*.json" --include="*.md" . 2>/dev/null | grep -v node_modules | head
```

No hits means the whole structure is hand-made in the dashboard and nothing in the
repo will ever populate it. Say so — it changes what the user has to build next.

## Report shape

1. Table of the roles that matter: id, position, created, subscribers, mentionable.
2. What changed since the previous read, diffed **by id**.
3. Every independent thing that is broken, each with the one call that proves it.
4. Explicit statement that nothing was written, plus the exact list of writes you
   would perform on confirmation.

A read-only audit that ends with "the role exists" is a failed audit. The user asked
because something does not work; name the thing.
