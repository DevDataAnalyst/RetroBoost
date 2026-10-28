# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- _Your contribution here._ See the [roadmap](docs/ROADMAP.md).

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

[Unreleased]: https://github.com/DevDataAnalyst/RetroBoost/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/DevDataAnalyst/RetroBoost/releases/tag/v1.0.0
