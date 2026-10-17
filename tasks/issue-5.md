# Issue 5: cast a public test stream (crunch)

Defaults picked in crunch mode:
- Protocol logic lives in a pure `CastController` (messages in, messages out) so it is unit-tested without a network. `CastSession` only does TLS I/O.
- TLS accepts the Chromecast's self-signed certificate, as the issue says. Checking that the device is genuine is a follow-up.
- Incoming JSON is parsed leniently with `JSONSerialization`; anything unexpected is ignored, and the message size is already capped at 64 KiB by `CastMessageDecoder`.
- Heartbeat: answer every `PING` with `PONG`, and send our own `PING` every 5 s.
- Test stream: Apple's `bipbop_4x3_variant.m3u8` (HTTPS, `application/x-mpegURL`).
- UI: a "Play test stream" button per device and a "Stop" button. #8 replaces these with the real cast.
- The 5-minute run uses the app's `--play-test-stream <host> --mute --seconds N` launch flag, because macOS gives Local Network access to the app, not to the `swift test` runner. `--mute` mutes the TV while it runs and restores the previous mute state. #8 removes the flag.

- [x] `CastController` start sends CONNECT + LAUNCH - unit test
- [x] PING gets PONG - unit test
- [x] RECEIVER_STATUS with `CC1AD845` sends CONNECT to the transport + LOAD with the URL - unit test
- [x] MEDIA_STATUS updates the player state; LAUNCH_ERROR / LOAD_FAILED fail - unit tests
- [x] `stop()` sends STOP with the session id - unit test
- [ ] `CastSession` over TLS to port 8009 - app launch flag against "Living Room TV" (192.168.0.104) stays PLAYING for 5+ minutes
