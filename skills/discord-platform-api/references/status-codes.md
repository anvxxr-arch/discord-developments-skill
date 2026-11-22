# Status Codes and Opcodes

Source: `topics/opcodes-and-status-codes.md`. Exact values.

## Gateway Opcodes

| Op | Name | Direction | Meaning |
|---|---|---|---|
| 0 | Dispatch | Receive | Event dispatched |
| 1 | Heartbeat | Send/Receive | Keep connection alive |
| 2 | Identify | Send | Start a new session |
| 3 | Presence Update | Send | Update presence |
| 4 | Voice State Update | Send | Join/leave/move voice channel |
| 6 | Resume | Send | Resume previous session |
| 7 | Reconnect | Receive | Reconnect and resume immediately |
| 8 | Request Guild Members | Send | Request offline members |
| 9 | Invalid Session | Receive | Session invalidated |
| 10 | Hello | Receive | Contains `heartbeat_interval` |
| 11 | Heartbeat ACK | Receive | Heartbeat acknowledged |
| 31 | Request Soundboard Sounds | Send | Read soundboard sounds |
| 43 | Request Channel Info | Send | Ephemeral channel data |

Note there is **no op 5**. `op 7` you never send; `op 9` you never send.

## Gateway Close Codes

| Code | Reason | Reconnect |
|---|---|---|
| 4000 | Unknown error | yes |
| 4001 | Unknown opcode / invalid payload | yes |
| 4002 | Decode error | yes |
| 4003 | Not authenticated (payload before Identify) | yes |
| 4004 | Authentication failed (bad token) | **no** |
| 4005 | Already authenticated (two Identifies) | yes |
| 4007 | Invalid `seq` on Resume | yes |
| 4008 | Rate limited (disconnected) | yes |
| 4009 | Session timed out | yes |
| 4010 | Invalid shard | **no** |
| 4011 | Sharding required | **no** |
| 4012 | Invalid API version | **no** |
| 4013 | Invalid intent(s) | **no** |
| 4014 | Disallowed intent(s) (privileged, not enabled) | **no** |

The "no reconnect" column is the discriminator: retrying 4004/4010–4014 in a loop is
what triggers the Cloudflare ban and burns the 1000-identify budget.

## Voice Opcodes

| Op | Name | Direction |
|---|---|---|
| 0 | Identify | client |
| 1 | Select Protocol | client |
| 2 | Ready | server |
| 3 | Heartbeat | client |
| 4 | Session Description | server |
| 5 | Speaking | client and server |
| 6 | Heartbeat ACK | server |
| 7 | Resume | client |
| 8 | Hello | server |
| 9 | Resumed | server |
| 11 | Clients Connect | server |
| 13 | Client Disconnect | server |
| 15 | Media Sink Wants | client and server |
| 21 | DAVE Prepare Transition | server |
| 22 | DAVE Execute Transition | server |
| 23 | DAVE Transition Ready | client |
| 24 | DAVE Prepare Epoch | server |
| 25 | DAVE MLS External Sender | server |
| 26 | DAVE MLS Key Package | client |
| 27 | DAVE MLS Proposals | server |
| 28 | DAVE MLS Commit Welcome | client |
| 29 | DAVE MLS Announce Commit Transition | server |
| 30 | DAVE MLS Welcome | server |
| 31 | DAVE MLS Invalid Commit Welcome | client |

## Voice Close Codes

| Code | Meaning | Reconnect |
|---|---|---|
| 4001 | Unknown opcode | new session |
| 4002 | Failed to decode payload | new session |
| 4003 | Not authenticated | new session |
| 4004 | Authentication failed | no |
| 4005 | Already authenticated | new session |
| 4006 | Session no longer valid (double Select Protocol) | new session |
| 4009 | Session timeout | new session |
| 4011 | Server not found | no |
| 4012 | Unknown protocol | new session |
| 4014 | Disconnected (kicked / gateway dropped) | **no** |
| 4015 | Voice server crashed | resume |
| 4016 | Unknown encryption mode | new session |
| 4017 | E2EE/DAVE protocol required | new session, with DAVE |
| 4020 | Bad request | new session |
| 4021 | Disconnected: rate limited | **no** |
| 4022 | Disconnected: call terminated (channel deleted) | **no** |

## HTTP Status Codes

| Code | Meaning |
|---|---|
| 200 | OK |
| 201 | Created |
| 204 | No Content |
| 304 | Not Modified |
| 400 | Bad Request — malformed payload |
| 401 | Unauthorized — missing/invalid `Authorization` |
| 403 | Forbidden — token lacks permission |
| 404 | Not Found — resource does not exist |
| 405 | Method Not Allowed |
| 429 | Too Many Requests |
| 502 | Gateway Unavailable — retry after a wait |
| 5xx | Server error (rare) |

**401 vs 403 is a real signal, not noise.** 401 = credential problem. 403 = credential
fine, permission or User-Agent problem. `403 code 40333` is the UA gate, not
permissions.

## JSON Error Codes (frequent)

| Code | Meaning |
|---|---|
| 0 | General error / malformed body |
| 10001 | Unknown account |
| 10002 | Unknown application |
| 10003 | Unknown channel |
| 10004 | Unknown guild |
| 10005 | Unknown integration |
| 10006 | Unknown invite |
| 10007 | Unknown member |
| 10008 | Unknown message |
| 10009 | Unknown permission overwrite |
| 10010 | Unknown provider |
| 20001 | Bots cannot use this endpoint |
| 20002 | Only bots can use this endpoint |
| 30001 | Maximum number of guilds reached (200) |
| 30005 | Maximum number of roles reached (250) |
| 30008 | Maximum number of emojis reached |
| 30010 | Maximum number of reactions reached |
| 30013 | Maximum number of channels reached (500) |
| 40001 | Unauthorized (bad token) |
| 40002 | Account is not verified |
| 40004 | Request entity too large |
| 40005 | Feature temporarily disabled |
| 40006 | Account banned from guild |
| 40007 | Invalid API version |
| 40008 | Invalid payload |
| 40009 | Invalid message |
| 40012 | Invalid message contents |
| 50001 | Missing Access — cannot see the resource |
| 50007 | Cannot send messages to this user |
| 50008 | Cannot send messages in a non-text channel |
| 50013 | Missing Permissions |
| 50016 | Invalid message type |
| 50035 | Invalid Form Body — parse `errors` recursively |

`50001` vs `50013` is the key diagnostic pair: 50001 means the bot cannot view the
channel (overwrite or membership), 50013 means it can view but lacks the specific
permission.
