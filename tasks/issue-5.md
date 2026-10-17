# Issue 5: cast a public test stream (crunch)

Defaults picked in crunch mode:
- Protocol logic lives in a pure `CastController` (messages in, messages out) so it is unit-tested without a network. `CastSession` only does TLS I/O.
- TLS accepts the Chromecast's self-signed certificate, as the issue says. Checking that the device is genuine is a follow-up.
- Incoming JSON is parsed leniently with `JSONSerialization`; anything unexpected is ignored, and the message size is already capped at 64 KiB by `CastMessageDecoder`.
- Heartbeat: answer every `PING` with `PONG`, and send our own `PING` every 5 s.
- Test stream: Apple's `bipbop_4x3_variant.m3u8` (HTTPS, `application/x-mpegURL`).
- No UI yet: `main` has no device list until #4 merges, so #8 adds the buttons.
- The 5-minute run uses the app's `--play-test-stream <host> --mute --seconds N` launch flag, because macOS gives Local Network access to the app, not to the `swift test` runner. `--mute` mutes the TV while it runs and restores the previous mute state. #8 removes the flag.

- [x] `CastController` start sends CONNECT + LAUNCH - unit test
- [x] PING gets PONG - unit test
- [x] RECEIVER_STATUS with `CC1AD845` sends CONNECT to the transport + LOAD with the URL - unit test
- [x] MEDIA_STATUS updates the player state; LAUNCH_ERROR / LOAD_FAILED fail - unit tests
- [x] `stop()` sends STOP with the session id - unit test
- [x] `CastSession` over TLS to port 8009 - app launch flag against "Living Room TV" (192.168.0.104): PLAYING 9 s after connecting, then no status change for the rest of a 5.5-minute run; TV idle afterwards

Found while verifying: loading the 30-minute test video as `LIVE` stalled in BUFFERING after about 2.5 minutes. `BUFFERED` fixed it; `LIVE` stays the default for our own capture.
