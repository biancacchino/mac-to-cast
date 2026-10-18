# Issue 7: capture a window to live HLS (crunch)

Defaults picked in crunch mode:
- `SCContentSharingPicker` in single-window mode. The system picker grants access to the picked window, so the app needs no Screen Recording permission.
- `SCStream` at up to 30 fps, scaled to at most 1920 px wide, plus the window's app audio (48 kHz stereo). The app's own audio is excluded.
- ScreenCaptureKit sends no new frame while the window is still, so the last frame is repeated at 10 fps; otherwise no segment would ever be cut.
- `AVAssetWriter` with `.mpeg4AppleHLS`: H.264 High (6 Mbit/s, a keyframe every second, no B-frames for lower latency) and AAC 128 kbit/s, cut into 1 s segments.
- The playlist lists the newest 6 segments; memory keeps the newest 12, so a slow client can still fetch one that just left the list.
- `EXT-X-TARGETDURATION` is the largest rounded segment duration seen so far, so it never goes down.
- Every new capture gets a fresh token and an empty store.
- The window shows the local playlist URL for testing in Safari; real UI is #10.

- [x] `LivePlaylist` - unit tests: first segment, sliding window and media sequence, target duration
- [x] `HLSStore.addSegment` - unit test: old segment data is dropped
- [x] `HLSSegmenter` - test with generated video and audio: an init segment and 1 s segments that AVFoundation reads back as a 2-track movie, and AVPlayer plays over the server
- [x] `WindowCapture` (`SCStream`) and `CaptureController` (picker, server, store)
- [x] A one-off run captured a real window: AVPlayer played the served playlist with video and sound tracks and 1 s segments
- [ ] Safari plays the local URL with sound while the window changes (manual)
