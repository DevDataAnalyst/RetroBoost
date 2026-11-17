# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- _Your contribution here._ See the [roadmap](docs/ROADMAP.md).

## [2.0.0] - 2026-11-17

The FluentCleaner update: the ideas, engines and rule files of [FluentCleaner](https://github.com/builtbybel/FluentCleaner), ported to PowerShell and the retro text UI. Credits and licenses: [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

### Added
- **APP CLEAN** (`A`): the 4,076-rule community **winapp2.ini** database (`data/Winapp2.ini`, CC BY-SA 4.0). Rules are detected per PC, grouped by category, scanned (`S`) and cleaned with `Detect`/`DetectFile`/`SpecialDetect`, `FileKey` patterns with `RECURSE`/`REMOVESELF`, `ExcludeKey` and `RegKey` support. Only cache, temp, log, crash, dump, thumbnail and telemetry rules start ticked; browser rules wait while that browser runs; sizes count only files that can really be deleted. Your own rules in `%LOCALAPPDATA%\RetroBoost\custom\*.ini`; your own exclusions in `config.json` (`"exclude"`).
- **TWEAKS** (`T`): FluentCleaner's 98-setting catalogue (`data/WinRules.ini`: ads, AI, appearance, Edge, Explorer, gaming, privacy, system, taskbar, updates) with live ON/off state, recommended set, undo to the Windows default, read-back verification, `[A]` locks for settings that need admin, variant groups and an Explorer restart on the result screen.
- **UNINSTALL** (`U`): Store apps and Control Panel programs, classified by FluentCleaner's `data/AppRules.ini` into suggested, yours and protected. Silent uninstall first (quiet uninstaller, then `msiexec`), the program's own window last, each removal verified.
- **AUTO**: `-Auto` (windowless safe clean, never stops programs), `-Auto -Shutdown`, and SETTINGS → **AUTO-CLEAN** (off, daily, weekly, at logon) using a Task Scheduler task for your account.
- **SETTINGS → BOOST+APP CLEAN**: BOOST can also run your APP CLEAN ticks (off by default).
- Two-column main menu with ten entries (`B D A R P T U S H Q`), shared scrolling lists with group headers (`← →` jumps between groups), an `ADMIN` badge when elevated.
- Self-test: 33 checks, now including the winapp2 engine (patterns, recursion, `ExcludeKey`, registry keys, files in use), the personal-folder and Windows-folder guards, a tweak applied and undone on a throwaway registry key, a real silent uninstall of a throwaway program entry, and `-Auto`.

### Changed
- BOOST, DISK CLEAN, RAM TRIM and STOP now share one plan/run/result pipeline with APP CLEAN, TWEAKS and UNINSTALL; the result screen shows only the sections that ran.
- Settings has two new rows; the kill list moved down accordingly.

### Not ported (on purpose)
- FluentCleaner's AI explanations and its winget uninstall step: both need the network, and RetroBoost makes no network calls.
- The cookie keep-list: cookie rules start unticked instead; it is on the [roadmap](docs/ROADMAP.md).

## [1.0.0] - 2026-10-28

First public release.

### Added
- **Retro text-mode UI** in PowerShell 7: BIOS-style boot splash, block-letter logo, double-line frames, gauges for disk, RAM and CPU, and three themes (blue, green, amber) with optional beeps.
- **BOOST NOW**: one action that cleans safe junk, trims RAM and closes the programs on your kill list, with a plan screen before it runs.
- **One-click launcher** (`RetroBoost-OneClick.cmd`): 3-second countdown (ESC cancels), then BOOST.
- **DISK CLEAN** with eight categories: user temp files (older than a day), package caches (npm, pip, uv, Yarn, bun, NuGet), browser caches (Brave, Chrome, Edge), updater downloads, VS Code leftovers, crash dumps, GPU shader caches (unticked) and the Recycle Bin (unticked). `W` opens *Settings → Storage* for Windows' own cleanup.
- **RAM TRIM** with a top-memory-users table and an honest note that relief is temporary.
- **PROCESSES** screen grouped by program, with a persistent **kill list**, polite close for windowed apps, an explicit force option, and a hard-protected list for Windows core, security tools and terminals.
- **Settings**: theme, sound, confirmation on/off, dry-run, and kill-list editing.
- **`-DryRun`** (change nothing), **`-Demo`** (invented data, nothing real is read or written), and an action **log** in `%LOCALAPPDATA%\RetroBoost`.
- **Test hooks** (`-Sandbox`, `-Keys`, `-Screenshot`, `-Dump`), a **sandbox self-test** and **CI** on Windows.
- **Screenshot renderer** (`tools/Render-Screenshots.ps1`) that paints README images from the app's own screen buffer.
- Documentation: README, [C: drive plan](docs/FREE-UP-C-DRIVE.md), [safety model](docs/SAFETY.md), [architecture](docs/ARCHITECTURE.md), [roadmap](docs/ROADMAP.md), contributing guide, code of conduct and security policy.

[Unreleased]: https://github.com/DevDataAnalyst/RetroBoost/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/DevDataAnalyst/RetroBoost/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/DevDataAnalyst/RetroBoost/releases/tag/v1.0.0
