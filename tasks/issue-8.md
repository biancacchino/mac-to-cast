# Issue 8: end to end, from the menu bar (crunch)

Decided with the user: the app is a menu bar app with a plain menu, like AirPlay (research in the #8 PR).

Defaults picked in crunch mode:
- No Dock icon and no window (`LSUIElement`). A TV symbol in the menu bar; it fills in while casting.
- Menu: "Cast a Window To" with one item per Chromecast (a checkmark on the active one), a status line, Stop Casting (Cmd-.), Quit (Cmd-Q). Items stay in place and are disabled when they do nothing, as the HIG asks.
- Choosing a Chromecast opens the system window picker; picking a window starts the capture and the cast. Choosing the window again from the system's sharing indicator restarts both, since the stream URL changes.
- The Cast connection is forced to IPv4. Its local address becomes the stream host, and its remote address is the only LAN address the HTTP server accepts.
- Stop and Quit send STOP to the TV first, so it goes back to idle.
- Frames fit in 1920x1080: Chromecasts decode H.264 up to level 4.1, and a 1920x1204 frame failed to load.
- `streamType` is `LIVE`. The `--play-test-stream` flag and the temporary capture row are removed.

- [x] Status line text - unit test for each Cast status
- [x] IPv4 address from an endpoint, as dotted text - unit test
- [x] `CastSession`: IPv4 only, URL built once connected, async `stop`, failure callback
- [x] `Caster` connects devices, picker, capture, server, and session; menu bar UI
- [x] On the TV (user): YouTube with picture and sound, about 7 s behind; Stop returns the TV to idle
- [x] Found on the TV and fixed: the server refused the TV (its address carried `%en0`), frames over 1080p failed to load, and LOAD now says the segments are fMP4

Found on the TV, left for later:
- The first ~10 s switch between buffering and playing, then play steadily. Waiting for 3 segments before casting did not help.
- Windows that are not 16:9 get black bars on the TV, as with AirPlay; cropping or stretching would be worse.
