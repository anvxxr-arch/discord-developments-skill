# Voice

Source: `topics/voice-connections.md`, `topics/opcodes-and-status-codes.md` (voice section).

## Flow Overview

Voice is not on the main gateway. It is four steps, each producing the input for the
next:

1. Bot sends `op 4 Voice State Update` on the **main** gateway with
   `{"guild_id": "...", "channel_id": "...", "self_mute": false, "self_deaf": false}`.
2. Gateway replies with `VOICE_STATE_UPDATE` (gives `session_id`) and
   `VOICE_SERVER_UPDATE` (gives `token` + `endpoint`).
3. Open a WebSocket to `wss://{endpoint}/?v=10` — no `?encoding=json` needed but
   harmless. Send `op 0 Identify` with `server_id` (= guild_id), `user_id`,
   `session_id`, `token`.
4. Receive `op 2 Ready` with `ssrc`, `ip`, `port`, `modes` → open UDP to `ip:port`,
   do IP discovery, then send `op 1 Select Protocol`.

`endpoint` from `VOICE_SERVER_UPDATE` **omits** the `wss://` scheme — prepend it.

## Voice Opcodes

| Op | Name | Direction |
|---|---|---|
| 0 | Identify | send |
| 1 | Select Protocol | send |
| 2 | Ready | receive |
| 3 | Heartbeat | send |
| 4 | Session Description | receive |
| 5 | Speaking | send |
| 6 | Heartbeat ACK | receive |
| 7 | Resume | send |
| 8 | Hello | receive |
| 9 | Resumed | receive |
| 11 | Clients Connect | receive |
| 13 | Client Disconnect | receive |
| 15 | Media Sink Wants | send |
| 21 | DAVE Prepare Transition | receive |
| 22 | DAVE Execute Transition | receive |
| 23 | DAVE Transition Ready | send |
| 24 | DAVE Prepare Epoch | receive |

Voice heartbeat uses its own `heartbeat_interval` from `op 8 Hello`; sequence numbers
in `op 3` are **nonces** (incrementing int), not the payload `s`.

## Select Protocol

```json
{"op": 1, "d": {"protocol": "udp",
  "data": {"address": "<external ip>", "port": <external port>, "mode": "aead_xchacha20_poly1305_rtpsize"}}}
```

Send **once per session**. Sending it again closes the socket with `4006`
(Session no longer valid). A successful resume preserves the selected protocol — do
not resend after resuming.

## IP Discovery

Before Select Protocol you need your external UDP address. Send a 74-byte packet to
the voice UDP port (all numerics **big endian**):

```
uint16 type = 0x0001
uint16 length = 0x0046 (70)
uint32 ssrc
66 bytes zero padding
```

Response is 74 bytes: `type` (2), `length` (2), `ssrc` (4), `address` (64, null-padded
ASCII), `port` (2). Use that address/port in Select Protocol.

Then send a 70-byte keepalive packet (`0x0001` type, ssrc, no address) every 5
seconds, or the UDP route silently stops passing traffic.

## Encryption Modes

| Name | Status |
|---|---|
| `aead_aes256_gcm_rtpsize` | preferred when available |
| `aead_xchacha20_poly1305_rtpsize` | mandatory — always offered |
| `xsalsa20_poly1305*` family | deprecated |

`aead_aes256_gcm_rtpsize` depends on CPU support (AES-NI). You **must** support
`aead_xchacha20_poly1305_rtpsize`; prefer AES-GCM when `modes` includes it.

Both AEAD modes use the RTP header as nonce input plus a 4-byte suffix appended to
the packet.

## DAVE / E2EE

Newer voice sessions negotiate end-to-end encryption via DAVE opcodes
(`21`–`31`: Prepare Transition, Execute Transition, Transition Ready, Prepare Epoch,
and MLS External Sender / Key Package / Proposals / Commit Welcome / Welcome /
Invalid Commit Welcome). If `op 2 Ready` advertises a `dave` version and the
connection does not complete the DAVE transition, audio is dropped while the socket
stays healthy — the failure looks like silence, not an error. Close code `4017` means
the channel requires DAVE and the client did not negotiate it.

## Speaking

Notify the server before sending audio:

```json
{"op": 5, "d": {"speaking": 1, "delay": 0, "ssrc": <ssrc>}}
```

`speaking` is a bitmask: `1 << 0` microphone, `1 << 1` soundshare, `1 << 2` priority.

## Media Sink Wants

By default you receive **every** user's audio in the channel. `op 15` lets you
subscribe narrowly:

```json
{"op": 15, "d": {"any": 0, "users": [{"user_id": "...", "sources": [{"source": 0, "max": 0}]}]}}
```

Use this to cut bandwidth on large channels.

## Voice Close Codes

| Code | Meaning |
|---|---|
| 4001 | Unknown opcode |
| 4002 | Failed to decode payload |
| 4003 | Not authenticated |
| 4004 | Authentication failed |
| 4005 | Already authenticated |
| 4006 | Session no longer valid — reselect protocol |
| 4009 | Session timeout |
| 4011 | Server not found |
| 4012 | Unknown protocol |
| 4014 | Disconnected (kicked / channel deleted) |
| 4015 | Server crashed |
| 4016 | Unknown encryption mode |
| 4017 | E2EE/DAVE required but unsupported by client |

## Practical Notes

- Do not attempt voice from a `Bot` token without `CONNECT` and `SPEAK`.
- `op 4 Voice State Update` with `channel_id: null` leaves the channel.
- `self_deaf: true` stops inbound audio at the server; the client also must not send.
- The voice WS URL from `VOICE_SERVER_UPDATE` is region-specific and can change on
  reconnect — always read it fresh.
