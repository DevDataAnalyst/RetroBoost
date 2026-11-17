# Roadmap and ideas

RetroBoost 2.0 does four things well: **clean regenerable junk (and 4,000+ apps' caches), switch off Windows' ads and telemetry, remove bloatware, and stop programs you chose, safely.** This page lists where it could go. **Everything here is open for contribution**: comment on (or open) an issue before you start, so we don't duplicate work.

Difficulty: 🟢 good first issue · 🟡 medium · 🔴 advanced. Every cleanup-related idea must respect the [safety model](SAFETY.md) (guards beat rules, admin optional, a sandbox test).

## Done in 2.0 (from FluentCleaner)

- [x] **App cleaners**: the winapp2.ini engine (APP CLEAN), with custom rules and exclusions.
- [x] **Tweaks**: FluentCleaner's settings catalogue with apply, read-back and undo.
- [x] **Uninstaller**: Store apps and programs, AppRules classification, silent-first.
- [x] **Non-interactive mode**: `-Auto`, `-Auto -Shutdown` and a Task Scheduler schedule in Settings.
- [x] **Cookie keep-list** (2.1): COOKIES screen, SQL edit instead of delete, every browser winapp2 knows.

## 🟢 Good first issues

- [ ] **Keep-list import and export.** Read and write a plain text file of sites (one per line), as FluentCleaner does; today the list lives in `config.json` (`keepCookies`).
- [ ] **Configurable protection.** Read extra protected program names and temp-skip folders from `config.json` (`protect`, `tempSkip`) instead of the author's hard-coded `claude` defaults.
- [ ] **More DISK CLEAN browsers.** Firefox, Opera, Vivaldi, Brave Beta/Nightly, Edge Beta (APP CLEAN already covers them through winapp2).
- [ ] **Tweak descriptions in other languages.** FluentCleaner keeps translated wording in `Lang\<culture>.ini` beside the catalogue; read the matching file if it exists.
- [ ] **More developer caches.** Gradle (`%USERPROFILE%\.gradle\caches`), Maven (`.m2\repository`), pnpm store, Cargo registry cache, Go build cache, Conda packages. Mark the "re-download is slow" ones as unticked.
- [ ] **ASCII fallback.** A `-Ascii` switch (and auto-detect) that replaces box-drawing and block characters for old consoles and fonts without them.
- [ ] **`-Version` and `-List`.** Print the version; list the categories and where they point, without scanning.
- [ ] **`-NoSplash`** (and a Settings toggle) for people who boot RetroBoost often.
- [ ] **More themes.** CGA magenta/cyan, Apple-II green, high-contrast. It is one hashtable in `$themes` (plus a screenshot).
- [ ] **Real screenshots and GIFs** of the app in real terminals (see [docs/screenshots](screenshots/README.md)).
- [ ] **Docs.** Translate the README and the [C: drive plan](FREE-UP-C-DRIVE.md); add tips for your Windows build.

## 🟡 Medium

- [ ] **Delete one site's cookies now.** FluentCleaner's Cookie Manager can remove the cookies of chosen sites on the spot; COOKIES could do the same behind a plan screen, reusing `SqlDelete`.
- [ ] **Search in the lists.** Type to filter APP CLEAN, TWEAKS and UNINSTALL (hundreds of rows on a busy PC).
- [ ] **Tweak packs.** Read extra `*.ini` catalogues from `%LOCALAPPDATA%\RetroBoost\tweaks\` (a later section with the same name replaces the earlier one, as in FluentCleaner).
- [ ] **Startup programs screen.** List startup entries (registry Run keys, Startup folder, scheduled tasks), show their impact, disable with a clear undo. Never delete.
- [ ] **Big-files explorer.** "Where did my space go?": a screen with the biggest folders and files on C:, a keystroke to open one in Explorer.
- [ ] **History and report.** Show past runs from `boost.log` (FluentCleaner keeps a junk-growth history); export the last run as Markdown or HTML.
- [ ] **Mouse support** in Windows Terminal (SGR mouse reporting).
- [ ] **Per-process CPU** and a small live sparkline on the RAM screen.
- [ ] **Windows PowerShell 5.1 support** (APP CLEAN uses `FileSystemName` and `[Convert]::ToHexString`, which need replacing).
- [ ] **Pester tests and PSScriptAnalyzer** in CI; split the self-test into focused cases.
- [ ] **Localisation.** Move UI strings into language files; start with a language you speak.
- [ ] **Installer helpers:** a Start Menu shortcut / Windows Terminal profile fragment.

## 🔴 Advanced

- [ ] **Optional admin mode for Windows' own junk** (Windows Update download cache with service stop/start, Delivery Optimization cache, `C:\Windows\Temp`) with explicit consent, a clear plan and a dry-run. Today the Windows folder is off limits to every cleaner.
- [ ] **Updating winapp2.ini** without breaking "no network": an explicit, opt-in download with a checksum, or a documented manual update.
- [ ] **Standby-list purge** (RAMMap-style) behind admin, with an honest explanation of the trade-off.
- [ ] **Safe duplicate-file finder** (hash-based) with a review screen. Never auto-delete.
- [ ] **Packaging and trust:** winget manifest, Scoop bucket, Chocolatey package, code-signed releases, reproducible zips.
- [ ] **A cross-platform sibling** (Linux/macOS) with its own category set.

## Not planned

To keep RetroBoost trustworthy, these are deliberately out of scope: registry *cleaners* that hunt for "orphaned" keys, "driver updaters", telemetry, ads, AI services and other network calls, and anything that deletes user documents.

## How to pick something up

1. Read [CONTRIBUTING.md](../CONTRIBUTING.md) and [ARCHITECTURE.md](ARCHITECTURE.md).
2. Open an issue (or comment on an existing one): *"I'd like to take X"*.
3. Open a draft pull request early; small PRs get reviewed fastest.

Have an idea that isn't listed? [Open a feature request](https://github.com/DevDataAnalyst/RetroBoost/issues/new/choose).
