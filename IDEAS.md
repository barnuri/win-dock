# WinDock — Ideas, Improvements & Big Dreams

A living backlog of everything we could do with WinDock: performance work, UI/UX polish,
general features, and moonshot dreams. Nothing here is committed — it's the "what if" file.

Legend: 🟢 quick win · 🟡 medium effort · 🔴 large project · 🚀 dream / moonshot

---

## 1. Performance

### Window Enumeration & AX Layer
- 🟢 **Adaptive cache TTL** — `WindowEnumerationService` uses a fixed 1-second cache; make the TTL adaptive (longer when the system is idle, shorter right after an app launch/quit event).
- 🟢 **Per-app cache invalidation** — invalidate only the cache entry for the app that fired the NSWorkspace notification instead of the whole window list.
- 🟡 **Incremental diffing** — compute a diff between old and new `dockApps` and publish only the changed items, so SwiftUI re-renders individual `AppDockItem`s instead of the whole array.
- 🟡 **AX observer subscriptions** — replace periodic re-enumeration with `AXObserver` callbacks (window created/destroyed/moved/title changed) per app, making the dock fully push-driven end-to-end.
- 🟡 **Priority lanes in `BackgroundTaskCoordinator`** — user-initiated actions (click, drag) get an express lane that bypasses debouncing; background churn stays debounced.
- 🔴 **ScreenCaptureKit migration** — replace `CGWindowListCreateImage` in `WindowPreviewView` with `SCScreenshotManager` / `SCStream`: GPU-backed, faster, and future-proof (CG APIs are deprecated).
- 🔴 **Persistent window index** — a small in-memory graph of window IDs ↔ apps ↔ spaces maintained by events, so "which windows does app X have" is an O(1) lookup, never a scan.

### Rendering & Memory
- 🟢 **Icon cache with cost limits** — `NSCache` for app icons rasterized once per size/scale, evicted under memory pressure.
- 🟢 **Preview thumbnail downsampling** — capture previews at the popover's actual pixel size instead of full window resolution.
- 🟡 **Lazy preview capture** — only start capturing window thumbnails after hover intent is confirmed (e.g. 150 ms dwell), cancel on exit.
- 🟡 **Metal-backed blur** — profile the glass material stack; if `NSVisualEffectView` layering is expensive on Intel/low-power machines, offer a "reduced effects" mode that swaps to flat translucency.
- 🟡 **Instruments CI gate** — a scripted Instruments (or `os_signpost`-based) run in CI that fails if main-thread hangs > 100 ms appear during a scripted stress test (launch/quit 20 apps).
- 🔴 **Zero-allocation update path** — audit `computeDockApps()` with the allocations instrument; reuse buffers and value types so a steady-state dock update allocates (almost) nothing.

### Energy & Idle Behavior
- 🟢 **App Nap friendliness** — verify the accessory app naps correctly when the dock is auto-hidden and no notifications are flowing.
- 🟡 **Battery-aware mode** — on battery, lengthen debounce intervals, disable live preview refresh, and pause badge polling.
- 🟡 **Energy dashboard in Settings** — show the user WinDock's own CPU wakeups/energy impact so we hold ourselves accountable.

---

## 2. UI / UX

### Taskbar Polish
- 🟢 **Running-indicator animation** — Windows 11-style subtle pill that widens on the active app, animated with a spring.
- 🟢 **Hover scale + tooltip refinement** — icon magnification on hover (configurable, off by default to stay "Windows-like").
- 🟢 **Badge overflow styling** — "99+" cap, colored badges per urgency, and a setting to disable badges per app.
- 🟡 **Drag-reorder physics** — smoother displacement animation while dragging icons (match Windows 11's slide-apart behavior).
- 🟡 **Small taskbar / large taskbar modes** — Windows 11's taskbar size options (small/medium/large) with proportional icon + preview scaling.
- 🟡 **Center vs. left alignment toggle** — already Windows-style centered? Offer classic left-aligned mode with the Start button pinned to the corner.
- 🟡 **Taskbar grouping modes** — "always combine", "combine when full", "never combine" (labels next to icons, like Windows' classic mode).
- 🔴 **Live thumbnails in the bar** — optional mode where each icon shows a miniature live window (like Windows' old "taskbar previews on hover" but embedded).

### Window Previews
- 🟢 **Fix unminimize on preview click** (already on ROADMAP) — clicking a minimized window's preview should restore it reliably.
- 🟢 **Keyboard navigation in previews** — arrow keys + Enter to pick a window while the popover is open.
- 🟡 **Live previews** — refresh thumbnails while the popover is open (ScreenCaptureKit stream at ~10 fps).
- 🟡 **Preview actions row** — per-window buttons: close, minimize, move to screen, move to space, tile left/right.
- 🟡 **Aero Peek** — hovering a preview temporarily makes all other windows transparent to "peek" at that window (Windows 7 nostalgia, genuinely useful).

### Start Menu
- 🟡 **Pinned + Recommended layout** — full Windows 11 start menu: pinned grid, "recommended" recent files (via NSMetadataQuery / recent documents), user avatar, power menu.
- 🟡 **Type-to-search everywhere** — start typing while the menu is open to filter apps instantly (fuzzy matching).
- 🟡 **App folders** — drag one app onto another in the start menu to create folders, Windows 11 style.
- 🔴 **Full Spotlight-grade search** — files, apps, settings panes, and web suggestions in the search flyout, backed by NSMetadataQuery with ranked results.

### System Tray & Widgets
- 🟡 **Real tray icon hosting** — mirror third-party menu bar items into the WinDock tray area (hard; may need AX scraping of the menu bar) — the "hidden icons" chevron flyout included.
- 🟡 **Clock flyout** — click the clock for a Windows 11-style calendar + notifications panel; integrate with EventKit for today's events.
- 🟡 **Quick Settings flyout** — Wi-Fi, Bluetooth, volume, brightness, focus modes, dark-mode toggle in one Windows 11-style panel.
- 🔴 **Widgets board** — swipe/click from the left corner: weather, calendar, stocks, RSS — a WidgetKit-host-like panel rendered by WinDock.

### Accessibility & Inclusivity
- 🟢 **Full VoiceOver audit** — labels, traits, and rotor actions for every dock item and preview.
- 🟢 **Reduce Motion / Reduce Transparency compliance** — respect system accessibility settings automatically.
- 🟢 **Keyboard-only operation** — a global hotkey to focus the dock, then full arrow-key navigation.
- 🟡 **High-contrast theme** and adjustable minimum hit-target sizes.
- 🟡 **RTL layout support** — mirrored layout for RTL locales; full localization pipeline (start with EN/HE).

### Theming
- 🟡 **Theme engine** — user-selectable accent colors, blur intensity, corner radius; light/dark/auto.
- 🟡 **Preset packs** — "Windows 11", "Windows 10", "Windows 7 Aero", "Fluent Dark", "macOS Native" hybrid.
- 🚀 **Community theme marketplace** — JSON-defined themes shareable via URL/gallery, hot-loaded without restart.

---

## 3. General Features

### Window Management
- 🟡 **Snap layouts** — hover the maximize area / hotkey to show Windows 11 snap-zone grids (halves, thirds, quarters) and place windows via AX. `WindowsResizeManager` is the seed of this.
- 🟡 **Snap groups** — remember snapped-together window sets and restore them as a group from the taskbar.
- 🟡 **Alt-Tab replacement mode** — optional WinDock-rendered ⌘Tab UI with window-level (not app-level) switching and live thumbnails.
- 🔴 **Virtual desktop (Spaces) integration** — Task View button shows all Spaces with drag-and-drop of windows between them; per-Space pinned apps.
- 🔴 **Window rules engine** — "Slack always opens on monitor 2, right half"; declarative per-app placement rules applied on window creation.

### Multi-Monitor
- 🟢 **Per-monitor dock settings** — position, size, auto-hide configured per screen instead of globally.
- 🟡 **Show windows on the monitor they live on** — taskbar mode: "all windows on every bar" vs "only this monitor's windows" (Windows has exactly this toggle).
- 🟡 **Monitor profiles** — detect home/office display arrangements and switch dock config automatically.

### Productivity
- 🟡 **Jump lists** — right-click an app for recent documents, frequent folders, and app-declared quick actions (recent docs via `NSDocumentController` / Spotlight).
- 🟡 **Taskbar pinned shortcuts** — pin files, folders, and URLs (not just apps) to the bar.
- 🟡 **Global hotkeys** — Win-key-style shortcuts: `⌥1`–`⌥9` activate the Nth dock item, `⌥T` toggles dock visibility.
- 🟡 **Clipboard history flyout** — `⌥V` opens a Windows-style clipboard history panel (opt-in, local only, encrypted at rest).
- 🟡 **Focus assist** — a do-not-disturb mode that suppresses badges and preview popovers during focus sessions; integrate with macOS Focus modes.
- 🔴 **Session restore** — snapshot all open apps + window positions as a named "workspace" and restore it later (morning setup in one click).

### Reliability & Quality
- 🟢 **Crash reporting (opt-in, privacy-respecting)** — MetricKit-based diagnostics, stored locally, user chooses to share.
- 🟢 **First-run onboarding** — a guided permissions flow (Accessibility, Automation, Screen Recording) with live status checks instead of raw system prompts.
- 🟡 **Private-API health checks** — startup self-test of `CGSGetWindowLevel` / `_AXUIElementGetWindow`; degrade gracefully and surface "compatibility mode" in Settings when an OS update breaks them.
- 🟡 **In-app updater** — Sparkle integration alongside the Homebrew tap, with delta updates and a release-notes panel.
- 🟡 **UI test harness** — XCUITest suite driving the dock end-to-end (launch app → icon appears → hover → preview shows) run in CI.
- 🟡 **Benchmark suite** — scripted scenario (open 30 windows across 5 apps) with recorded update latency, published per release so regressions are visible.

### Distribution & Community
- 🟢 **Proper website / landing page** with screenshots, GIFs, and the Homebrew one-liner.
- 🟡 **Mac App Store feasibility study** — probably impossible with AX private APIs, but a sandboxed "lite" edition might be viable.
- 🟡 **Signed + notarized DMG releases** in addition to the tap.
- 🟡 **Localization program** — community translations via a simple strings-file workflow.

---

## 4. Big Dreams 🚀

- 🚀 **WinDock Sync** — settings, pinned apps, themes, and workspaces synced across Macs via iCloud (CloudKit, end-to-end encrypted).
- 🚀 **Plugin SDK** — a Swift/JS extension API for third-party tray widgets, jump-list providers, and search sources; sandboxed plugin processes with an XPC boundary.
- 🚀 **The full "Windows shell" suite** — WinDock + WinExplorer (Files-style file manager) + WinSettings (single settings hub) as a family of apps for switchers.
- 🚀 **AI assistant in the search flyout** — local-first Copilot-style panel: ask "open my standup notes and Slack", it orchestrates apps/windows via the rules engine. On-device model or user-supplied API key; nothing leaves the machine by default.
- 🚀 **Voice control** — "snap Safari left, Xcode right" via Speech framework, mapped to the snap-layout engine.
- 🚀 **Live tiles, done right** — opt-in animated tiles in the start menu fed by app widgets (WidgetKit extraction) — the good part of Windows 8, without the rest of Windows 8.
- 🚀 **Timeline** — a scrubber of your day: which windows/documents were active when, so you can jump back to "what I was doing at 11:30" (all data local, encrypted).
- 🚀 **Game bar** — an overlay (FPS, capture, DND) that appears over full-screen games, reusing `FullscreenDetectionManager`.
- 🚀 **Companion iPhone app** — your Mac's taskbar in your pocket: see badges, trigger workspaces, use the phone as a mini tray via local network (Bonjour + encrypted transport).
- 🚀 **WinDock for teams** — shared workspace definitions ("the on-call layout") distributed to a team via a config repo.

---

## 5. Tech Debt & Housekeeping

- 🟢 Split `SettingsView.swift` (56 KB) into per-tab files.
- 🟢 Split `AppManager.swift` (40 KB) — extract pinning/persistence, activation, and drag-reorder into focused types.
- 🟢 Expand `ROADMAP.md` (currently one line) or fold it into this file.
- 🟡 Increase unit-test coverage beyond `AppManagerTests` — `BackgroundTaskCoordinator` debounce timing, `WindowEnumerationService` filtering rules, and `NotificationPositionManager` deserve dedicated tests with mocks.
- 🟡 Adopt Swift 6 strict concurrency mode and fix all sendability warnings — the actor/`@MainActor` architecture is already close.
- 🟡 Document the private-API surface in one place (`PrivateAPIs.swift` + a doc page) with per-macOS-version compatibility notes.

---

*Last updated: 2026-07-03. Add ideas freely — this file is meant to grow.*
