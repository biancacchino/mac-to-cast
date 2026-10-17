# Issue 6: local HTTP server (crunch)

Defaults picked in crunch mode:
- Paths sit under a random UUID token (122 random bits): `/<token>/live.m3u8`, `/<token>/init.mp4`, `/<token>/seg-<n>.m4s`. The server answers on the whole LAN and must send `Access-Control-Allow-Origin: *` (the Cast receiver is a web page), so without a secret path any device or web page could read the stream. Wrong token or unknown path: 404.
- `init.mp4` is added to the issue's two paths: fMP4 HLS needs an initialization segment (`EXT-X-MAP`), which #7 will produce.
- Content types: `application/vnd.apple.mpegurl`, `video/mp4`, `video/iso.segment`. Playlist is `Cache-Control: no-cache`.
- Only `GET` and `HEAD`; other methods get 405. The request head is capped at 8 KiB (431 beyond), and a connection still open 10 s after it was accepted is closed. One request per connection (`Connection: close`).
- Content is served from memory only; there is no file system access, so no path traversal surface.
- The listener picks a free port.
- Only loopback and an allow-list of IPv4 addresses may connect (empty by default; #8 adds the Chromecast). Added after the security pass, so other LAN devices can neither read the stream nor use up the 32 connection slots.
- `Cache-Control: no-store` and `X-Content-Type-Options: nosniff` on every response.

- [x] Request parsing - unit tests: GET, HEAD, query string, malformed, other method, oversized head
- [x] Routing and headers - unit tests: each path and type, wrong token, unknown path, HEAD has no body
- [x] `HLSServer` on `NWListener` - integration test over loopback with `URLSession`
- [x] `curl -i` against a running instance shows the status and headers
