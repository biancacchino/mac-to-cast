# Issue 6: local HTTP server (crunch)

Defaults picked in crunch mode:
- Paths sit under a random UUID token (122 random bits): `/<token>/live.m3u8`, `/<token>/init.mp4`, `/<token>/seg-<n>.m4s`. The server answers on the whole LAN and must send `Access-Control-Allow-Origin: *` (the Cast receiver is a web page), so without a secret path any device or web page could read the stream. Wrong token or unknown path: 404.
- `init.mp4` is added to the issue's two paths: fMP4 HLS needs an initialization segment (`EXT-X-MAP`), which #7 will produce.
- Content types: `application/vnd.apple.mpegurl`, `video/mp4`, `video/iso.segment`. Playlist is `Cache-Control: no-cache`.
- Only `GET` and `HEAD`; other methods get 405. The request head is capped at 8 KiB (431 beyond), and a connection that sends nothing for 10 s is closed. One request per connection (`Connection: close`).
- Content is served from memory only; there is no file system access, so no path traversal surface.
- The listener picks a free port.

- [ ] Request parsing - unit tests: GET, HEAD, query string, malformed, other method, oversized head
- [ ] Routing and headers - unit tests: each path and type, wrong token, unknown path, HEAD has no body
- [ ] `HLSServer` on `NWListener` - integration test over loopback with `URLSession`
- [ ] `curl -i` against a running instance shows the status and headers
