# Native Mac App Design Brief
### Design principles distilled from Things 3, Bear, Craft, Fantastical, Raycast, Zed, and Mimestream

---

## 1. Typography

- **Primary typeface:** SF Pro (system font) - don't fight the platform. Custom display fonts only for branding moments (à la Bear), never for body/UI text.
- **Hierarchy through weight & size, not color.** Use 3-4 weight/size steps max: Title (Semibold, 17-20pt), Section headers (Semibold, 13-15pt), Body (Regular, 13pt), Secondary/meta (Regular, 11-12pt, reduced opacity).
- **Line height:** 1.4-1.5x for body text; tighter (1.1-1.2x) for titles.
- **Avoid all-caps** except for tiny section labels (e.g. sidebar group headers), and even then keep them small and low-contrast.

## 2. Color

- **One accent color.** Pick a single tint (system blue is safe, but a custom accent - Bear's honey/amber, Things' blue - builds identity). Everything else stays grayscale.
- **Grayscale does the structural work.** Backgrounds, borders, and secondary text should live in system gray steps (`labelColor`, `secondaryLabelColor`, `tertiaryLabelColor`, `separatorColor`) so they auto-adapt to light/dark and increase-contrast accessibility settings.
- **Respect Dark Mode as a first-class design, not an inverted palette.** True dark backgrounds (near-black, not gray-on-gray) read as more premium - see Mimestream.
- **Semantic color only for state** (red = destructive/error, green = success), used sparingly.

## 3. Materials & Depth

- Use **vibrancy/blur (`NSVisualEffectView` / SwiftUI `.background(.regularMaterial)`)** for sidebars, toolbars, and floating panels - this is the single biggest "feels native" signal.
- **System-standard corner radii**: 10-12pt for windows/panels, 6-8pt for buttons and list rows, 4pt for small controls.
- **Soft, subtle shadows** - never hard drop shadows. macOS shadows are diffuse and low-opacity.
- Avoid flat, opaque "web app" panels with no translucency; it's the fastest way to look like a port.

## 4. Layout & Spacing

- **8pt spacing grid** (4pt for tight control clusters). Consistent padding inside list rows, cards, and panels (12-16pt is a good default).
- **Sidebar + content** is still the most "Mac-native" structural pattern (Things, Bear, Craft, Mail, Finder). Use `NavigationSplitView` in SwiftUI to get this for free, including collapsing/resizing behavior.
- **Generous whitespace** over dense information. When in doubt, remove a border and add padding instead.
- Toolbar items should use SF Symbols at consistent weights, not custom icon sets that clash with system chrome.

## 5. Motion

- **Spring-based, physical motion** - not linear ease in/out. SwiftUI's `.spring()` or `.interactiveSpring()` defaults are tuned for this; use them rather than custom curves.
- **Motion should confirm an action**, not decorate the screen. A checkbox animating a strikethrough, a card settling into place after drag - yes. Bouncing logos or attention-seeking idle animations - no.
- Keep animation durations short: 150-300ms for most UI transitions, up to 400ms for larger view changes.

## 6. Iconography

- **SF Symbols first.** They auto-match weight, scale with Dynamic Type, and adapt to color modes for free.
- If custom icons are needed (app icon, feature glyphs), match SF Symbols' stroke weight and optical size so they don't look foreign next to system icons.
- App icon: follow Apple's rounded-square template exactly (use Apple's icon template files) - don't freehand the corner radius or gloss/gradient style, it's an instant "non-native" tell.

## 7. Interaction & System Integration

- **Keyboard-first parity.** Every primary action needs a shortcut; power users on Mac expect this (Raycast, Things, Zed all live or die by their keyboard layer).
- **Native menu bar menu** with proper submenus and standard placement (App menu, File, Edit, View, Window, Help) - don't collapse everything into a hamburger menu, that's an iOS/web pattern.
- **Support system features**: widgets, Shortcuts/App Intents, drag-and-drop, Quick Look, Handoff/Continuity, multiple windows, Stage Manager compatibility.
- **Respect window resizing.** Native apps handle arbitrary window sizes gracefully - a fixed-size app immediately signals "cross-platform port."

## 8. Anti-patterns to avoid

- Electron-style flat white toolbars with no vibrancy
- Custom title bars that don't match system traffic-light spacing
- Web-style hamburger menus and hover-only interactions (Mac is pointer + keyboard, not touch)
- Overly saturated, multi-color palettes competing with system UI
- Ignoring Dark Mode until the end ("dark mode as an afterthought" always shows)

---

*Use this as a north star during design and code review: if a screen doesn't fit one of these bullets, ask why not before shipping it.*
