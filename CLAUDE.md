# mac-to-cast

Native macOS app that casts any window to a Chromecast over local HLS.

## Overrides
None yet. See "Agents committing" in `tasks/todo.md`.

## Repo map
- `tasks/todo.md` - plan, issue list, open decisions

## Run locally
- `swift build` / `swift test`
- `scripts/build-app.sh && open build/MacToCast.app` (once issue 1 lands)
- Find Chromecasts: `dns-sd -B _googlecast._tcp`

## Stack
Swift 6, SwiftUI, ScreenCaptureKit, AVFoundation, Network.framework. macOS 14+. No third-party dependencies.

## Decisions (ADRs)
- Transport is local HLS to the Default Media Receiver (`CC1AD845`): free, all Swift, about 2-5 s latency. Low-latency Cast Streaming is deferred.
- CastV2 protobuf is hand-encoded; do not add a protobuf dependency.
- Swift package plus `scripts/build-app.sh`, not an Xcode project.

## Conventions
- One issue per branch (`issue-<n>`), small commits, Conventional Commits.
- Run `swift test` before calling anything done.
- UI follows the design brief in `docs/design-brief.md`.
