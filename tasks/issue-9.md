# Issue 9: notice when a window blocks capture (crunch)

Found on the real Netflix window, which changed the plan:
- ScreenCaptureKit hands over frames of protected video as protected IOSurfaces (`IOSurfaceProtectionOptions = 1`).
  The H.264 encoder fails on them (`-17691`), which ended the cast at once ("connected, then shut off").
- The CPU cannot read them as black either: a black-pixel check read 0% black.
  So the first plan (at least half the frame black for 2 s) could never have worked, and it is gone.

What it does now:
- Each captured frame is checked for the protection flag. A protected frame is replaced with a black frame of the same size and time, so the cast keeps going with sound.
- The menu's status line says "This window blocks screen capture, so the TV shows black" while frames are protected, and clears when they are not.
- A dark or black window never triggers it: only the flag does.
- The flag is an undocumented IOSurface creation property. If a future macOS drops it, the encoder fails again, and the cast ends with "Can't encode this window. If it plays protected video, it blocks screen capture".

- [x] `ProtectedFrame.isProtected` - unit test with an ordinary and a protected buffer
- [x] `ProtectedFrame.black` - unit test: video-range black
- [x] Wired into `WindowCapture` and the menu status line
- [x] Netflix in a browser (user): the TV shows black with sound, and the notice shows. Netflix also blanks its own video on the laptop while it is captured; subtitles stay, since they are page text.
- [x] A dark window (T3) casts normally with no notice
