# mac-to-cast plan

Cast any macOS window (an app, or a browser tab via its window) to a Chromecast.
DRM-protected windows (Netflix and friends) are out of scope: ScreenCaptureKit gives black frames for them, and we just tell the user.

## How it works

1. The user picks a window in the system picker (`SCContentSharingPicker`).
2. `SCStream` captures that window's video and audio.
3. `AVAssetWriter` with the `.mpeg4AppleHLS` profile encodes H.264/AAC and cuts 1 s fMP4 segments, so we write no muxer.
4. A tiny HTTP server (`NWListener`) on the Mac serves the live playlist and segments from memory.
5. The app talks CastV2 to the Chromecast: TLS on port 8009, length-prefixed protobuf `CastMessage`.
   It launches the free Default Media Receiver (`CC1AD845`) and sends `LOAD` with our playlist URL.
6. The Chromecast pulls the stream over Wi-Fi.

Expected latency is about 2-5 s, which is fine for video and not for interactive use (that would need Cast Streaming via openscreen, deferred).

## Stack

- Swift 6 package, SwiftUI app as an executable target, macOS 14+.
- Apple frameworks only: ScreenCaptureKit, AVFoundation, Network, SwiftUI.
  No third-party dependencies; the protobuf message is six fields, so we encode it by hand.
- Tests: Swift Testing via `swift test` (needs Xcode selected via `xcode-select`, but no Xcode project).
- `scripts/build-app.sh` wraps the binary in a `.app` with an `Info.plist` and signs it with a local self-signed identity (ad-hoc if missing).

## Workflow

- Each item below is a GitHub issue (#2-#11).
- One Sonnet session per issue: `claude -w issue-<n> --model sonnet`.
- The agent works on branch `issue/<n>`, commits, runs `swift test`, and pushes.
  PRs merge with a merge commit or rebase (squash is off), and only after the `test` check passes.
- One read-only review agent at the end, before `/ship`.

## Issues

- [x] **#2 Scaffold the package and CI**
  `Package.swift`, empty SwiftUI window, test target, `scripts/build-app.sh` (Info.plist with `NSLocalNetworkUsageDescription` and `NSBonjourServices = _googlecast._tcp`), CI running `swift build` and `swift test`.
  Verify: `swift test` passes; `scripts/build-app.sh && open build/MacToCast.app` shows a window; CI green; then `protect-main biancacchino/mac-to-cast <job>`.
- [x] **#3 CastV2 message framing**
  Encode and decode `CastMessage` (4-byte big-endian length + protobuf fields 1-6).
  Verify: unit tests round-trip known byte sequences, including a payload over 127 bytes (multi-byte varint).
- [x] **#4 Discover Chromecasts**
  `NWBrowser` for `_googlecast._tcp`, friendly name from the TXT record `fn`.
  Verify: unit test for TXT parsing; app lists both Chromecasts on this network (`dns-sd -B _googlecast._tcp` shows two).
- [x] **#5 Cast a public test stream**
  TLS connect (accept the device's self-signed cert), `CONNECT`, `PING`/`PONG` heartbeat, `LAUNCH CC1AD845`, `LOAD` Apple's bipbop sample HLS URL.
  Verify: the TV plays the sample video and keeps playing for 5+ minutes (heartbeat works). This proves the Cast side before any capture code.
- [x] **#6 Local HTTP server**
  `NWListener` serving `/<token>/live.m3u8`, `/<token>/init.mp4`, and `/<token>/seg-<n>.m4s` from memory, 404 otherwise.
  Only loopback and the Chromecast's address may connect; the token is a random UUID.
  Verify: unit test of request parsing; `curl -i` against a running instance returns the right headers.
- [x] **#7 Capture a window to live HLS**
  System picker, `SCStream` video + app audio, `AVAssetWriter` segments into a sliding-window playlist.
  Defaults: `tasks/issue-7.md`.
  Verify: Safari plays `http://localhost:<port>/live.m3u8` with sound while the captured window changes.
- [ ] **#8 End to end**
  A menu bar app: pick a Chromecast, then a window, cast; URL uses the Mac's LAN IP taken from the Cast connection's local endpoint.
  Defaults: `tasks/issue-8.md`.
  Verify on the TV: a YouTube tab with audio, a Finder window, a code editor; note the measured latency.
- [ ] **#9 DRM / black-frame notice**
  If captured frames stay black for ~2 s, show "This window blocks screen capture".
  Verify: cast a Netflix tab, see the notice; a dark-themed window does not trigger it.
- [ ] **#10 Native UI pass**
  Polish the menu bar menu: icon states, wording, a way back in if the menu bar item is hidden, first-launch hint, dark mode, keyboard use.
  Verify: screenshots in light and dark, keyboard-only walkthrough.
- [ ] **#11 Review and ship**
  One read-only review agent, then `/ship` or `comprehend`.

## Decided

- **CI cost:** the repo is public, so GitHub Actions minutes are free, including macOS runners.
- **Agents committing:** agents may commit and push on their own `issue/<n>` branch only; opening PRs and merging stays with me.

- **Signing:** ad-hoc signing changed the signature on every build, so macOS forgot Local Network permission after each rebuild (#17).
  `scripts/make-signing-identity.sh` creates a self-signed identity once; `build-app.sh` signs with it.

- **Menu bar app:** the app is a menu bar item with a plain menu, like AirPlay, not a window (#8).
  Apple's HIG prefers a menu over a popover for menu bar extras, and a desktop widget would need an app extension, which needs an Xcode project.

## Open decisions

None right now.
