# Webhooks

Source: `platform/webhooks.md`, `resources/webhook.md`.

## Two Different Things

1. **Incoming webhook** — an HTTP endpoint Discord creates for a channel. Anyone with
   the URL can post. No bot token needed.
2. **Interactions / events endpoint** — your server receiving Discord's POSTs
   (covered in `interactions.md`).

This chapter is (1).

## Executing

```
POST /webhooks/{webhook.id}/{webhook.token}
```

**No `Authorization` header.** The token in the URL is the credential. Adding an
`Authorization` header is harmless but pointless; sending a wrong one is not.

Query params:

| Param | Type | Meaning |
|---|---|---|
| `wait` | bool | return the created message object instead of `204` |
| `thread_id` | snowflake | post into a thread on the webhook's channel |
| `with_components` | bool | allow `IS_COMPONENTS_V2` (components-only) payload |

Without `wait=true` you get `204 No Content` and no id — you cannot edit or delete
what you just sent. Always pass `wait=true` when you need the message id.

Body accepts the same shape as `POST /channels/{id}/messages` plus webhook-only
overrides: `username`, `avatar_url`, `thread_name` (forum channels), `applied_tags`,
`flags`, `components`, `poll`.

`thread_name` is required when posting to a forum (`GUILD_FORUM`) or media channel
via webhook — that is how a webhook creates a forum post.

## GitHub / Slack Compatibility

Append `/github` or `/slack` to the webhook URL to accept those payload shapes:

```
POST /webhooks/{id}/{token}/github
POST /webhooks/{id}/{token}/slack
```

Both ignore the `wait` param semantics you'd expect. With `/slack`, `wait=true` is
required to get the message object.

## Webhook Object

`id`, `type`, `guild_id?`, `channel_id?`, `user?`, `name?`, `avatar?`, `token?`,
`application_id?`, `source_guild?`, `source_channel?`, `url?`.

`type`: `1` Incoming, `2` Channel Follower, `3` Application.

- `token` is only returned by `GET /webhooks/{id}` when the requester is the bot that
  created it — otherwise it is `null`. A webhook whose token you cannot read is
  unmovable by URL.
- `GET /webhooks/{id}/{token}` needs no auth and returns the webhook without `token`.

## Management

```
POST   /channels/{channel.id}/webhooks          # create; requires MANAGE_WEBHOOKS
GET    /channels/{channel.id}/webhooks
GET    /guilds/{guild.id}/webhooks
GET    /webhooks/{webhook.id}
PATCH  /webhooks/{webhook.id}
DELETE /webhooks/{webhook.id}
GET    /webhooks/{webhook.id}/{webhook.token}
PATCH  /webhooks/{webhook.id}/{webhook.token}
DELETE /webhooks/{webhook.id}/{webhook.token}
POST   /webhooks/{webhook.id}/{webhook.token}/slack
POST   /webhooks/{webhook.id}/{webhook.token}/github
```

The `{id}/{token}` variants need no `Authorization` header. The bare `{id}` variants
require a bot token and `MANAGE_WEBHOOKS`.

## Message Endpoints on a Webhook

```
GET    /webhooks/{webhook.id}/{webhook.token}/messages/{message.id}
PATCH  /webhooks/{webhook.id}/{webhook.token}/messages/{message.id}
DELETE /webhooks/{webhook.id}/{webhook.token}/messages/{message.id}
GET    /webhooks/{webhook.id}/{webhook.token}/messages/{message.id}/... 
```

Edits via webhook token only work on messages **the same webhook** created. A webhook
cannot edit a user's message.

## Failure Modes

| Symptom | Cause |
|---|---|
| `401 Unauthorized` | wrong/rotated token, or webhook deleted |
| `404 Unknown Webhook` | id+token pair does not exist |
| `400 Invalid Form Body` | payload too large or embed budget blown |
| `204` but nothing visible | `wait` omitted and channel is not where you looked |
| message lands in wrong channel | `thread_id` given for a thread in another channel |
| `50008` | posting directly to a forum channel instead of using `thread_name` |

## Applications vs Incoming

An application-owned webhook (`type: 3`) is the interaction followup endpoint, driven
by `application_id` + interaction token, not a stored webhook token. Do not try to
reuse an interaction token as a webhook token after 15 minutes.

## Rate Limits

Webhook execution shares the per-webhook bucket. Same headers, same 429 handling as
the rest of the API.
