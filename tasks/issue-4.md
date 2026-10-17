# Issue 4: discover Chromecasts (crunch)

Defaults picked in crunch mode (no checkpoints):
- Identity is the TXT `id`; the Bonjour instance name is the fallback. `fn` is display only, since users rename devices and names can repeat.
- TXT values come from any device on the LAN: the name is trimmed, capped at 64 characters, and falls back to the instance name when empty.
- The list is rebuilt from the browser's full result set on every change, sorted by name, deduplicated by `id`.
- A browser failure (for example Local Network access denied) shows a message instead of an empty list.

- [x] `CastDevice(instanceName:txt:endpoint:)` parsing - unit tests for normal, missing `fn`, blank `fn`, long `fn`, missing `id`
- [x] `DeviceBrowser` wraps `NWBrowser` for `_googlecast._tcp` - checked by running the app
- [x] Window lists devices, shows "Looking for Chromecasts..." while empty and the error text on failure - checked by running the app; screenshot not possible from the agent (no Screen Recording permission), left as a manual PR step
- [x] `swift test` green; the running app logged `Found 2 Chromecasts: ["Living Room TV", "Living Room TV 3"]`
