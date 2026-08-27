# Changelog

## 1.0.4 - 2026-08-27

- Fixes Quick Launcher category and slot routing so System/Create/Games edits never fall back to Daily slot 1.
- Uses a validated route request file instead of mutable RunCommand parameters, and rejects mismatched completion results.
- Prevents overlapping settings dialogs and verifies all 20 slots for both save and clear operations.
- Saves each configured Windows shortcut icon as a validated per-slot PNG, honoring custom `.lnk` icons and Unicode names/paths.
- Launches Unicode and Edge App / PWA `.lnk` files through Windows ShellExecute, preserving shortcut arguments such as `--app-id` and profile selection.
- Routes launches through a validated request file and rejects stale category/slot results instead of silently opening another shortcut.

## 1.0.3 - 2026-08-27

- Reworks Quick Launcher add/edit into one contextual panel with inline validation, clear button hierarchy, Enter/Escape behavior, and no MessageBox interruption.
- Makes clear a two-step action inside the same panel and removes per-slot stale icon assets after clear or URL replacement.
- Adds explicit left-click/right-click discovery hints and distinct saved, cleared, and category-renamed result states.

## 1.0.2 - 2026-08-25

- Fixes Quick Launcher shortcuts stored in paths containing Chinese or other Unicode characters.
- Routes launches through a hidden Unicode-safe Windows PowerShell bridge while keeping configuration-driven slots and graceful missing-file feedback.
- Stops exposing raw shortcut paths in Rainmeter tooltips, avoiding ANSI mojibake from Lua 5.1.

## 1.0.1 - 2026-08-25

- Fixes Todo add and refresh under Windows PowerShell 5.1 while retaining UTF-8 BOM, hash-conflict protection, atomic replacement, and backups.
- Makes the Todo input panel focus reliably and prevents stale result replay when the panel is opened.
- Repairs Quick Launch shortcut configuration, including EXE/LNK/URL validation, icon extraction, cancellation, detailed errors, and visible panel feedback.

## 1.0.0 - 2026-08-25

- First public package of the neutral frosted-glass dashboard.
- Includes Clock, Calendar, Markdown Todo, four persistent Focus timers, optional ActivityWatch usage, and configurable Quick Launch.
- Adds clean first-run state without personal tasks, usage history, timer progress, or launcher paths.
