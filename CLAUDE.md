# mac-to-cast

Native macOS app that casts any window to a Chromecast over local HLS.

## Overrides
- Agents may commit and push on their own `issue/<n>` branch without asking (`n` is the GitHub issue number).
  If the worktree branch has another name, rename it first: `git branch -m issue/<n>`.
- Still ask before opening a PR, merging, or touching any other branch.

## Repo map
- `tasks/todo.md` - plan, issue list, open decisions

## Run locally
- `swift build` / `swift test` (needs `xcode-select -p` pointing at Xcode.app; the Command Line Tools toolchain cannot find the `Testing` module)
- One-time: `scripts/make-signing-identity.sh` (stable signature, so macOS keeps permissions across rebuilds)
- `scripts/build-app.sh && open build/MacToCast.app`
- Find Chromecasts: `dns-sd -B _googlecast._tcp`
- App logs: `/usr/bin/log stream --info --predicate 'subsystem == "com.biancacchino.MacToCast"'`
- Test cast (until #8): `open build/MacToCast.app --args --play-test-stream <chromecast-ip> --mute --seconds 20`. The first run must be started from your own terminal so macOS shows the Local Network prompt.

## Stack
Swift 6, SwiftUI, ScreenCaptureKit, AVFoundation, Network.framework. macOS 14+. No third-party dependencies.

## Decisions (ADRs)
- Transport is local HLS to the Default Media Receiver (`CC1AD845`): free, all Swift, about 2-5 s latency. Low-latency Cast Streaming is deferred.
- CastV2 protobuf is hand-encoded; do not add a protobuf dependency.
- Swift package plus `scripts/build-app.sh`, not an Xcode project.

## Conventions
- One issue per branch (`issue/<n>`), small commits, Conventional Commits, `Closes #<n>` in the PR.
- Run `swift test` before calling anything done.
- UI follows the design brief in `docs/design-brief.md`.
