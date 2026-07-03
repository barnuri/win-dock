# WinDock Development Roadmap

The full idea backlog — performance, UI/UX, features, and moonshots — lives in [IDEAS.md](IDEAS.md).
This file tracks near-term priorities and what has shipped.

## Up next
- Fix unminimize issue when clicking on minimized window preview
- Keyboard navigation in window previews (arrow keys + Enter)
- Lazy preview capture (dwell-confirmed hover before capturing)
- Global hotkeys (⌥1–⌥9 activate Nth dock item)
- Split SettingsView.swift and AppManager.swift into focused files

## Recently shipped (2026-07-03)
- Adaptive window-enumeration cache TTL (1s during churn, 5s when quiet)
- Coordinator priority lanes — user actions bypass debouncing; battery-aware delays
- NSCache-backed app icon cache
- Window preview thumbnail downsampling (440px max width)
- Windows 11-style running indicator (dot ↔ pill spring morph)
- Reduce Motion / Reduce Transparency compliance
- VoiceOver labels, values, and hints for dock items
- Private-API health check at startup with graceful degradation logging
