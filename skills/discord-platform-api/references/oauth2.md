# OAuth2

Source: `topics/oauth2.md`, `platform/oauth2-and-permissions.md`.

## Flows

| Flow | Use |
|---|---|
| Authorization code | user-facing install, get a `code` → exchange for token |
| Client credentials | app-only, no user; server-to-server |
| Bot authorization (no OAuth2 code) | add bot to guild with scopes straight from the authorize URL |
| Implicit / `token` response type | **not supported** — use code + PKCE |

## Authorize URL

```
https://discord.com/oauth2/authorize?
  client_id=<app_id>&
  response_type=code&
  redirect_uri=<urlencoded>&
  scope=identify%20guilds&
  state=<opaque>&
  code_challenge=<S256(challenge)>&        # PKCE, optional but recommended
  code_challenge_method=S256&
  permissions=<bitfield>&                   # bot scope only
  guild_id=<prefill>&                       # bot scope only
  disable_guild_select=true                 # bot scope only
```

- `state` is echoed back on the redirect. Generate it, store it, verify it.
- `prompt=consent` forces the consent screen again (needed to re-issue a refresh
  token for an already-authorized app).
- `redirect_uri` must exactly match one registered in the Developer Portal.

## Token Exchange

```
POST /oauth2/token
Content-Type: application/x-www-form-urlencoded
Authorization: Basic base64(client_id:client_secret)      # optional but supported
```

Body: `grant_type=authorization_code`, `code=<code>`, `redirect_uri=<same as authorize>`.
With PKCE add `code_verifier`.

Client credentials: `grant_type=client_credentials`, `scope=<space separated>`.

Response:

```json
{"access_token": "...", "token_type": "Bearer", "expires_in": 604800,
 "refresh_token": "...", "scope": "identify guilds"}
```

`expires_in` = 604800 seconds = 7 days.

Refresh: `grant_type=refresh_token`, `refresh_token=...`. A refreshed token may
return a **new** refresh token — store whatever comes back, replacing the old one.

Revoke: `POST /oauth2/token/revoke` with `token=<access or refresh>` and
`token_type_hint`.

## Scopes

| Scope | Grants |
|---|---|
| `identify` | `GET /users/@me` |
| `email` | `email` field on the user object (requires `identify`) |
| `connections` | `GET /users/@me/connections` |
| `guilds` | `GET /users/@me/guilds` |
| `guilds.join` | add the authorized user to a guild |
| `guilds.members.read` | read a member object in a guild you bot is not in |
| `gdm.join` | add user to a group DM |
| `bot` | install the bot + `applications.commands` |
| `applications.commands` | register commands on the user's behalf |
| `applications.commands.update` | update commands |
| `applications.entitlements` | read entitlements |
| `webhook.incoming` | create a webhook in a channel the user picks |
| `role_connections.write` | write linked roles metadata |
| `rpc`, `rpc.activities.write`, `rpc.notifications.read`, `rpc.voice.read`, `rpc.voice.write` | local RPC |
| `messages.read` | read messages via the local RPC/chat |
| `voice` | join voice |

`bot` and `applications.commands` are combined by Discord when you request `bot`.

## webhook.incoming

Unique among scopes: it does **not** return a token you then use. It creates a
webhook and returns it in the redirect's `guild_id`/`webhook` query params:

```
?code=...&guild_id=...&webhook={"id":"...","token":"..."}
```

Parse `webhook` as URL-encoded JSON. This is the only OAuth2 flow that yields a
long-lived credential for a specific channel.

## Bot Authorization Without a Code

Add `scope=bot` (plus `applications.commands`) to the authorize URL and the bot is
installed on redirect — no token exchange needed. The redirect carries
`guild_id`, `permissions`, and `code` (discard the code, or exchange it, both fine).

`permissions` is the bitfield to request. Omitting it requests the full set the app
was configured with; a user can always deselect, so never assume you got what you
asked for — re-check with `GET /guilds/{id}/roles` and your own member's roles.

## Token Usage

`Authorization: Bearer <access_token>` — not `Bot`. Same endpoints, same rate limits,
identity is the authorizing user. Any endpoint requiring bot permissions will 403
unless that user has them.

## Security Notes

- Never put `client_secret` in client-side code; the code exchange belongs on your
  server.
- Always validate `state`. Always validate the `redirect_uri` matches exactly.
- Access tokens are 7 days; refresh tokens do not expire unless revoked or the user
  removes the app.
- A stolen user token is full impersonation of that user for its scopes — treat it
  like a password, not like a bot token.
- `identify` alone is low value; `guilds.join` and `webhook.incoming` are the scopes
  worth auditing for abuse.
