# Formatting and CDN Images

Source: `reference.md` § Message Formatting, § Image Formatting, § Image Data,
§ Signed Attachment CDN URLs.

## Mention and Entity Syntax

| Type | Syntax |
|---|---|
| User | `<@USER_ID>` |
| User (legacy `!`) | `<@!USER_ID>` — deprecated, treat as normal mention |
| Channel | `<#CHANNEL_ID>` |
| Role | `<@&ROLE_ID>` |
| Game profile | `<@$GAME_ID>` |
| Slash command | `</NAME:COMMAND_ID>` |
| Slash + subcommand | `</foo bar:123456789012345678>` |
| Slash + group + subcommand | `</foo group bar:123456789012345678>` |
| Custom emoji | `<:NAME:ID>` |
| Animated emoji | `<a:NAME:ID>` |
| Unix timestamp | `<t:1618953630>` |
| Styled timestamp | `<t:1618953630:d>` |

Mentions ping **only if** the sender has `MENTION_EVERYONE` (for `@everyone`/`@here`)
and `allowed_mentions` permits the target. Both gates apply — formatting alone does
not ping.

## Timestamp Styles

| Style | Output | Meaning |
|---|---|---|
| `t` | 16:20 | Short time |
| `T` | 16:20:30 | Medium time |
| `d` | 20/04/2021 | Short date |
| `D` | April 20, 2021 | Long date |
| `f` | April 20, 2021 at 16:20 | **default** |
| `F` | Tuesday, April 20, 2021 at 16:20 | Full date, short time |
| `s` | 20/04/2021, 16:20 | Short date + time |
| `S` | 20/04/2021, 16:20:30 | Short date + medium time |
| `R` | 4 years ago | Relative |

Timestamps are **seconds**, rendered in each viewer's own timezone and locale. This
is the correct way to emit a time — never hardcode a timezone string.

## Guild Navigation

`<id:customize>`, `<id:browse>`, `<id:guide>`, `<id:linked-roles>`,
`<id:linked-roles:ROLE_ID>` (opens the connection modal for that role).

## CDN Base and Transforms

```
https://cdn.discordapp.com/
```

- Change format by swapping the extension: `.jpg` `.jpeg` `.png` `.webp` `.gif` `.json` (Lottie).
- Change size with `?size=N` — **any power of two from 16 to 4096**.
- Animated assets have hashes prefixed `a_`; request them as `.webp?animated=true`.
- Animated WebP/AVIF uploads do **not** convert cleanly to GIF — request WebP for
  compatibility regardless of original format.

## Endpoint Paths

| Asset | Path |
|---|---|
| Custom emoji | `emojis/{emoji_id}.png` |
| Guild icon | `icons/{guild_id}/{icon}.png` |
| Guild splash | `splashes/{guild_id}/{splash}.png` |
| Guild banner | `banners/{guild_id}/{banner}.png` |
| User banner | `banners/{user_id}/{banner}.png` |
| User avatar | `avatars/{user_id}/{avatar}.png` |
| Member avatar | `guilds/{guild_id}/users/{user_id}/avatars/{member_avatar}.png` |
| Default avatar | `embed/avatars/{index}.png` |
| App icon | `app-icons/{application_id}/{icon}.png` |
| Role icon | `role-icons/{role_id}/{icon}.png` |
| Sticker | `stickers/{sticker_id}.png` |

Default avatar `index`:
- new username system: `(user_id >> 22) % 6`
- legacy discriminator system: `discriminator % 5`

Sticker GIFs bypass the CDN base: `https://media.discordapp.net/stickers/{sticker_id}.gif`.

## Signed Attachment URLs

Uploaded attachments get `?ex=&is=&hm=` signed URLs with a preset expiry:

| Param | Meaning |
|---|---|
| `ex` | hex timestamp — expiry |
| `is` | hex timestamp — issued at |
| `hm` | signature valid until expiry |

- Standard CDN endpoints above are **not** signed and never expire.
- When passing an attachment URL into an API field (`embed.image.url`,
  webhook `avatar_url`), pass it **without** query params — Discord re-signs and
  refreshes it.
- A stored signed URL **will** expire. Re-fetch the message rather than caching the
  URL for later use.

## Image Data

Data URI form, JPG/GIF/PNG only:
`data:image/png;base64,<BASE64>`. Content type must match the actual bytes.

## File Type Filtering

Up to 10 values in file-upload components and slash command options. Each is either a
group name or a dot-prefixed extension (`.pdf`, case-insensitive).

| Group | Extensions |
|---|---|
| `image` | `.png` `.gif` `.jpg` `.jpeg` `.jfif` `.webp` `.avif` |
| `video` | `.mp4` `.mov` `.qt` `.webm` |
| `audio` | `.mp3` `.m4a` `.wav` `.ogg` `.opus` `.flac` |

**This checks the filename extension only — it does not inspect content.** Validate
actual file bytes yourself. Prefer group names over individual extensions; do not
hardcode the lists, they change.

## Locales

Discord locale codes include `id` (Indonesian / Bahasa Indonesia), `da`, `de`,
`en-GB`, `en-US`, `es-ES`, and more. Used for command `name_localizations` /
`description_localizations` and returned as `locale` / `guild_locale` on interactions.
