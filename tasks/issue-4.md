# Issue 4: discover Chromecasts (crunch)

Defaults picked in crunch mode (no checkpoints):
- Identity is the TXT `id`; the Bonjour instance name is the fallback. `fn` is display only, since users rename devices and names can repeat.
- TXT values come from any device on the LAN: the name is trimmed, capped at 64 characters, and falls back to the instance name when empty.
- The list is rebuilt from the browser's full result set on every change, sorted by name, deduplicated by `id`.
- A browser failure (for example Local Network access denied) shows a message instead of an empty list.

- [ ] `CastDevice(instanceName:txt:endpoint:)` parsing - unit tests for normal, missing `fn`, blank `fn`, long `fn`, missing `id`
- [ ] `DeviceBrowser` wraps `NWBrowser` for `_googlecast._tcp` - checked by running the app
- [ ] Window lists devices, shows "Looking for Chromecasts..." while empty and the error text on failure - checked by running the app and a screenshot
- [ ] `swift test` green; both home Chromecasts ("Living Room TV", "Living Room TV 3") appear in the app
