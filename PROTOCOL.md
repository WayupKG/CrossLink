# CrossLink Wire Protocol v1 (LAN MVP)

This is an independently specified protocol shared by Swift and Kotlin clients.
It is **not** compatible with KDE Connect.

## Pairing (out-of-band)

Mac displays a QR code with a URI:

`crosslink://pair?host=192.168.1.10&port=48321&key=<base64url-no-padding-of-32-random-bytes>`

The 256-bit random pairing secret is generated with OS CSPRNG and stored in macOS Keychain.
Android stores the QR URI encrypted using an AES-256 GCM Android Keystore key.
Anyone who can photograph this QR code or copy the URI can authenticate: show it only to a trusted device.
The Mac app allows revoking all paired devices by rotating its key.

## Reconnect and discovery

The QR host is only a starting point. When it does not answer, Android looks up Bonjour service
`_crosslink._tcp` and picks the instance whose TXT record `id` equals

`hex(HMAC-SHA256(key = QR secret, "crosslink/v1/discovery")[0:8])` (16 lowercase hex chars),

which identifies the pairing without revealing the secret. The found address is saved only after a
successful handshake; a key mismatch there counts as an ordinary failed attempt (a TXT record can be
spoofed). A key mismatch at the QR address means the Mac was re-paired: Android stops and asks for
a new QR scan. Otherwise Android retries with pauses of 1, 2, 4 … 30 s until the user disconnects.

## Framing

One TCP connection, length-prefixed frames:

- 4 bytes: big-endian unsigned payload length
- 1–524288 bytes: payload

Receivers must reject zero-length / oversized frames. Android reads exactly N bytes
using DataInputStream; macOS buffers partial NWConnection reads before parsing.

## Handshake

1. Android -> Mac plaintext JSON:
   `{"type":"hello","version":1,"nonce":"<base64 of 32 random bytes>"}`
2. Mac -> Android plaintext JSON:
   `{"type":"hello_ack","version":1,"nonce":"<base64 of 32 random bytes>"}`
3. `salt = androidNonce || macNonce` (64 bytes)
4. Derive each direction's 32-byte AES key with **HKDF-SHA256**:
   - input keying material: 32-byte QR secret
   - salt: 64-byte nonce concatenation (not hashed)
   - info: UTF-8 `crosslink/v1/mac-to-android` or `crosslink/v1/android-to-mac`
   - output length: 32 bytes
5. All subsequent frames: **AES-256-GCM** with a fresh random 12-byte IV. Wire
   payload: `IV(12) || CIPHERTEXT || TAG(16)`. JSON is inside ciphertext.
6. Mac -> Android authenticated encrypted `{"type":"ready","seq":1,"text":"Mac готов"}`
7. Android -> Mac authenticated encrypted `{"type":"ready_ack","seq":1,"text":""}`
8. Both peers are considered authenticated only after successful encrypted messages.

## Encrypted messages

`{"type":"text"|"clipboard"|"ping"|"pong"|"bye","seq":2,"text":"..."}`

File messages (below) carry their own fields instead of `text`.

- Each direction independently starts sequence numbering at 1 (including ready/ready_ack).
- Receiver demands *exactly* previous sequence + 1; replay and out-of-order frames fail closed.
- Text max 20,000 UTF-8 bytes; UI may truncate incoming display to 20,000 characters.
- `clipboard`: receiver replaces clipboard contents with the string.
- `text`: receiver only shows it in the app.
- `ping` / `pong`: keepalive. Android sends `ping` every 20 s; the receiver answers `pong`.
  Android treats 45 s without any frame as a dead link, the Mac drops a phone after 60 s.
- `bye` (Mac → Android): the user disconnected on the Mac; Android stops reconnecting.
- No plaintext payload or secret is logged to disk.

## Files

Either side can send files; they go one after another, each with a random 128-bit `id`
(32 lowercase hex chars). All messages are ordinary encrypted messages with `seq`.

1. Sender → receiver: `{"type":"file_start","id":"…","name":"IMG_0042.jpg","size":1234567,"mime":"image/jpeg"}`.
   `size` is the byte count, or `-1` when the source does not know it.
2. Sender → receiver, repeated: `{"type":"file_chunk","id":"…","data":"<base64>"}` with at most
   196,608 raw bytes (262,144 base64 chars), so a sealed chunk stays far below the 512 KiB frame.
   The sender reads the next chunk only after the previous one is written to the socket: TCP
   backpressure keeps memory flat, and pings, texts and `file_done` of other files slip in between.
3. Sender → receiver: `{"type":"file_end","id":"…","sha256":"<64 lowercase hex of the whole file>"}`.
4. Receiver → sender: `{"type":"file_done","id":"…","ok":true|false}`. `ok:false` may also come
   before `file_end` (no space, too many files at once); the sender then stops sending that file.
5. Sender → receiver: `{"type":"file_cancel","id":"…"}` when the source became unreadable.

Receiver rules:

- At most 4 incoming files at a time and 4 GiB per file; anything else is answered `ok:false`.
- More bytes than the announced `size`, a different byte count at the end, or a SHA-256 mismatch
  discard the file and answer `ok:false`.
- The name is only a hint: keep its last path component, drop control characters and `:`,
  strip leading dots and spaces, cut to 120 characters keeping the extension, `file` if empty.
- Data is written to a temporary/pending file and becomes visible only after the hash matches.
  The Mac saves to `~/Downloads` (a free name like `photo 2.jpg`) with the quarantine attribute,
  so Gatekeeper checks an app or script before it runs. Android saves photos to
  `Pictures/CrossLink`, videos to `Movies/CrossLink`, everything else to `Download/CrossLink`.
- A dropped connection discards half-received files; there is no resume.

## Security and limitations

- Application-layer authenticated encryption protects against passive LAN interception.
- A user must deliberately scan the QR (or paste its URI). There is no centralized identity provider.
- Mac keeps one authenticated phone. A new TCP connection is handled separately and replaces
  the phone only after it completes the handshake (`ready_ack`), so a stray LAN connection to the
  port cannot drop it. At most one unauthenticated handshake at a time, closed after 10 s.
  Multiple device pairing is not implemented.
- Key rotation on Mac invalidates any Android device's saved credentials.
- The Mac listener binds to all local interfaces. Do not forward TCP port 48321
  to the public Internet; keep it behind a trusted LAN firewall.
- Files are accepted from the paired device without asking; pairing is the trust decision.
- No transfer of notification content or SMS.
- The Android connection is **not guaranteed to remain alive in the background**.
- This design requires on-device review and penetration testing before real-world
  distribution. QR codes should be short-lived in a future production version.
