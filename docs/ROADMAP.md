# Roadmap and ideas

RetroBoost 1.0 does one thing well: **clean regenerable junk, trim RAM and stop programs you chose, safely.** This page lists where it could go. **Everything here is open for contribution**: comment on (or open) an issue before you start, so we don't duplicate work.

Difficulty: 🟢 good first issue · 🟡 medium · 🔴 advanced. Every cleanup-related idea must respect the [safety model](SAFETY.md) (regenerable data, no admin by default, a sandbox test).

## 🟢 Good first issues

- [ ] **Configurable protection.** Read extra protected program names and temp-skip folders from `config.json` (`protect`, `tempSkip`) instead of the author's hard-coded `claude` defaults.
- [ ] **More browsers.** Firefox, Opera, Vivaldi, Brave Beta/Nightly, Edge Beta: add cache paths and the process check. *(Firefox keeps caches under `%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*\cache2`: verify before adding.)*
- [ ] **Chat and media app caches.** Discord, Slack, Microsoft Teams, Spotify and similar Electron apps keep large caches. Find the paths, confirm they regenerate, add categories with a running-app guard.
- [ ] **More developer caches.** Gradle (`%USERPROFILE%\.gradle\caches`), Maven (`.m2\repository`), pnpm store, Cargo registry cache, Go build cache, Conda packages. Mark the "re-download is slow" ones as unticked.
- [ ] **ASCII fallback.** A `-Ascii` switch (and auto-detect) that replaces box-drawing and block characters for old consoles and fonts without them.
- [ ] **`-Version` and `-List`.** Print the version; list the categories and where they point, without scanning.
- [ ] **`-NoSplash`** (and a Settings toggle) for people who boot RetroBoost often.
- [ ] **More themes.** CGA magenta/cyan, Apple-II green, high-contrast. It is one hashtable in `$themes` (plus a screenshot).
- [ ] **Real screenshots and GIFs** of the app in real terminals (see [docs/screenshots](screenshots/README.md)).
- [ ] **Docs.** Translate the README and the [C: drive plan](FREE-UP-C-DRIVE.md); add tips for your Windows build.

## 🟡 Medium

- [ ] **Startup programs screen.** List startup entries (registry Run keys, Startup folder, scheduled tasks), show their impact, disable with a clear undo. Never delete.
- [ ] **Big-files explorer.** "Where did my space go?": a screen with the biggest folders and files on C:, a keystroke to open one in Explorer. The parallel scanner pattern is in the repo history of the author's tooling and easy to port.
- [ ] **History and report.** Show past BOOSTs from `boost.log`; export the last run as Markdown or HTML.
- [ ] **Non-interactive mode** (`-Auto`) for Task Scheduler: runs the safe categories with no prompts, logs everything, exits with a code. Needs very careful guardrails.
- [ ] **Mouse support** in Windows Terminal (SGR mouse reporting).
- [ ] **Per-process CPU** and a small live sparkline on the RAM screen.
- [ ] **Windows PowerShell 5.1 support** (no `ForEach-Object -Parallel`, `[EnumerationOptions]`, ternary or `??` used today, so this may be small).
- [ ] **Pester tests and PSScriptAnalyzer** in CI; split the self-test into focused cases.
- [ ] **Localisation.** Move UI strings into language files; start with a language you speak.
- [ ] **Installer helpers:** a Start Menu shortcut / Windows Terminal profile fragment.

## 🔴 Advanced

- [ ] **Optional admin mode** for categories that need elevation (Windows Update download cache with service stop/start, Delivery Optimization cache, `C:\Windows\Temp`, WER report archive, setup logs) with explicit consent, a clear plan and a dry-run.
- [ ] **Standby-list purge** (RAMMap-style) behind admin, with an honest explanation of the trade-off.
- [ ] **Safe duplicate-file finder** (hash-based) with a review screen. Never auto-delete.
- [ ] **Plug-in categories:** user-defined categories in `categories.d/*.json` with the same safety checks.
- [ ] **Packaging and trust:** winget manifest, Scoop bucket, Chocolatey package, code-signed releases, reproducible zips.
- [ ] **A cross-platform sibling** (Linux/macOS) with its own category set.

## Not planned

To keep RetroBoost trustworthy, these are deliberately out of scope: registry cleaners, "driver updaters", telemetry, ads, any network calls, and anything that deletes user documents.

## How to pick something up

1. Read [CONTRIBUTING.md](../CONTRIBUTING.md) and [ARCHITECTURE.md](ARCHITECTURE.md).
2. Open an issue (or comment on an existing one): *"I'd like to take X"*.
3. Open a draft pull request early; small PRs get reviewed fastest.

Have an idea that isn't listed? [Open a feature request](https://github.com/DevDataAnalyst/RetroBoost/issues/new/choose).
