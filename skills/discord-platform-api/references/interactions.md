# Interactions

Source: `interactions/receiving-and-responding.md`, `events/webhook-events.md`,
`interactions/application-commands.md`.

## Two Mutually Exclusive Transports

An app receives interactions **either** via the `INTERACTION_CREATE` gateway event
**or** via an HTTP Interactions Endpoint URL. Never both. The webhook path needs no
persistent connection, which makes it the right choice for serverless.

## Interaction Types

| Name | Value |
|---|---|
| `PING` | 1 |
| `APPLICATION_COMMAND` | 2 |
| `MESSAGE_COMPONENT` | 3 |
| `APPLICATION_COMMAND_AUTOCOMPLETE` | 4 |
| `MODAL_SUBMIT` | 5 |

## Callback Types (response `type`)

| Name | Value | Use |
|---|---|---|
| `PONG` | 1 | ACK a PING |
| `CHANNEL_MESSAGE_WITH_SOURCE` | 4 | Respond immediately |
| `DEFERRED_CHANNEL_MESSAGE_WITH_SOURCE` | 5 | ACK now, edit later; user sees loading state |
| `DEFERRED_UPDATE_MESSAGE` | 6 | Components: ACK, edit original later; no loading state |
| `UPDATE_MESSAGE` | 7 | Components: edit the message the component is on |
| `APPLICATION_COMMAND_AUTOCOMPLETE_RESULT` | 8 | Autocomplete choices |
| `MODAL` | 9 | Popup modal |
| `PREMIUM_REQUIRED` | 10 | Deprecated |
| `LAUNCH_ACTIVITY` | 12 | Activities only |

## The Two Deadlines

- **3 seconds** to send the initial response. Miss it and the token is invalidated.
- Token remains valid **15 minutes** afterwards for followups/edits.

Because of this: never do slow work before responding. Return `type: 5` immediately,
then `PATCH /webhooks/{application.id}/{interaction.token}/messages/@original`.

With `DEFERRED_CHANNEL_MESSAGE_WITH_SOURCE`, the only valid message flag is
`EPHEMERAL`. For `IS_COMPONENTS_V2` you must defer first and edit the original
response — you cannot send it in the deferral itself.

## Followups

```
POST   /webhooks/{application.id}/{interaction.token}
GET    /webhooks/{application.id}/{interaction.token}/messages/{message.id}
PATCH  /webhooks/{application.id}/{interaction.token}/messages/{message.id}
DELETE /webhooks/{application.id}/{interaction.token}/messages/{message.id}
PATCH  /webhooks/{application.id}/{interaction.token}/messages/@original
```

Followups behave like Execute Webhook but `wait` is always true. `thread_id`,
`avatar_url`, and `username` are **not supported** here. `EPHEMERAL` (`1 << 6`) and
`IS_COMPONENTS_V2` (`1 << 15`) flags are allowed.

Limit: **5 followup messages** per interaction when the app is user-installed and
not installed in the server (`authorizing integration owners` contains only
`USER_INSTALL`).

## Endpoint Security (mandatory)

Every request carries:

- `X-Signature-Ed25519`
- `X-Signature-Timestamp`

Validate Ed25519 over `timestamp + raw_body` using the app's `public_key`. Return
`401` on failure. Discord routinely sends **deliberately invalid signatures** as a
security check — fail the check and the endpoint URL is removed, with an email and
System DM.

`PING` arrives as a POST with `{"type": 0}`; answer **`204` with an empty body** to
pass endpoint verification. Note the interaction PING answer is `type: 1` (`PONG`)
inside the callback body, while the webhook-events PING is a bare `204`.

Hash the **raw** request body bytes, not a re-serialized dict — any JSON
normalization breaks the signature.

## Command Registration

```
POST   /applications/{application.id}/commands                      # global
POST   /applications/{application.id}/guilds/{guild.id}/commands    # guild
```

- Global commands propagate slowly and have read-repair (a stale use is rejected
  and triggers a reload). Guild commands update **instantly** — use them for
  testing, global for release.
- Name regex for `CHAT_INPUT` names and option names:
  `^[-_\u02BC\p{L}\p{N}\p{sc=Deva}\p{sc=Thai}]{1,32}$` with the unicode flag.
  Lowercase variant required where one exists. `USER`/`MESSAGE` commands may be
  mixed case with spaces.
- Limits: 100 global `CHAT_INPUT` commands.
- `options` is only valid on `CHAT_INPUT`.
- Cannot have two global `CHAT_INPUT` with the same name, nor two guild ones in the
  same guild. Global + guild with the same name is allowed.

### Command types

| Name | Value |
|---|---|
| `CHAT_INPUT` (slash) | 1 |
| `USER` | 2 |
| `MESSAGE` | 3 |
| `PRIMARY_ENTRY_POINT` | 4 |

No `PRIMARY_ENTRY_POINT` guild commands.

### Option types

| Name | Value | Note |
|---|---|---|
| `SUB_COMMAND` | 1 | |
| `SUB_COMMAND_GROUP` | 2 | |
| `STRING` | 3 | |
| `INTEGER` | 4 | -2^53+1 .. 2^53-1 |
| `BOOLEAN` | 5 | |
| `USER` | 6 | |
| `CHANNEL` | 7 | |
| `ROLE` | 8 | |
| `MENTIONABLE` | 9 | |
| `NUMBER` | 10 | double, -2^53 .. 2^53 |
| `ATTACHMENT` | 11 | |

In interaction data, `value` and `options` are mutually exclusive — `options` means
the option is a subcommand/group.

## Webhook Events (opposite direction)

Discord POSTs to your endpoint; used for `APPLICATION_AUTHORIZED`,
`APPLICATION_DEAUTHORIZED`, `ENTITLEMENT_*`, `QUEST_USER_ENROLLMENT`, and
`LOBBY_MESSAGE_*` / `GAME_DIRECT_MESSAGE_*`.

Payload wrapper:

```json
{"version": 1, "application_id": "...", "type": 1, "event": {"type": "...", "timestamp": "...", "data": {...}}}
```

`type` 0 = PING, 1 = event.

- Answer **`204` within 3 seconds**. Otherwise Discord retries with exponential
  backoff for up to **10 minutes**, then stops sending and notifies by email.
- Same Ed25519 signature validation requirement as interactions.
- For actioned events, consider deduping on something in `data` — retries mean
  duplicate deliveries are possible.
