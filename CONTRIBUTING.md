# Contributing to RetroBoost

Thank you for considering a contribution! RetroBoost is a small, friendly, open project, and **help from developers around the world is exactly how it gets more powerful**. You don't need to be a PowerShell expert: docs, screenshots, translations, testing and ideas are all valuable.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to help

| You are... | You could... |
|---|---|
| Someone with a PC | run it (start with `-Demo`), tell us what confused you, test on your Windows build, terminal and font |
| A writer or translator | improve the [C: drive plan](docs/FREE-UP-C-DRIVE.md), the README, or translate them |
| A designer | create themes, an ASCII fallback, better layouts, screenshots and GIFs |
| A PowerShell developer | add categories, fix bugs, pick items from the [roadmap](docs/ROADMAP.md) |
| A security-minded reviewer | audit the [safety model](docs/SAFETY.md) and try to make it touch something it shouldn't |

Browse the [roadmap](docs/ROADMAP.md) for ideas marked 🟢 good first issue, 🟡 medium and 🔴 advanced.

## Quick start for contributors

You need Windows 10/11 and [PowerShell 7](https://github.com/PowerShell/PowerShell).

```powershell
git clone https://github.com/<your-user>/RetroBoost.git     # your fork
cd RetroBoost
pwsh -File src/retroboost.ps1 -Demo                          # explore with invented data
pwsh -File tests/selftest.ps1                                # must print "all checks passed"
```

Useful while developing (details in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)):

```powershell
pwsh -File src/retroboost.ps1 -Demo -Screenshot all          # every screen as plain text
pwsh -File src/retroboost.ps1 -Demo -Keys b,enter            # a scripted BOOST, frame by frame
pwsh -File tools/Render-Screenshots.ps1                      # regenerate docs/screenshots/*.png
```

## Principles (please keep these)

1. **Safety first.** RetroBoost deletes files, writes settings, uninstalls apps and stops programs. Read [docs/SAFETY.md](docs/SAFETY.md) before changing anything destructive.
2. **Regenerable data by default.** No documents, photos, downloads or anything the user can't get back. Anything riskier starts unticked, and the guards (`Test-Never`, `Test-Keep`) are never weakened.
3. **No admin by default.** Elevated features must be opt-in, explicit and guarded (like the `[A]` tweaks).
4. **Transparent.** Plan before action, a dry-run path, and a log line for every action. No network calls, no telemetry.
5. **Readable.** One script anyone can audit in an evening. Prefer a clear 5 lines to a clever 1.

## Add a cleanup category

The most common contribution. Checklist:

- [ ] **The data regenerates by itself** (or by re-downloading), and you can say how. If it doesn't, it doesn't belong here.
- [ ] **The path is user level** (under `%LOCALAPPDATA%`, `%APPDATA%`, `%TEMP%` or the user profile) and exists on a normal install. State the app and version you checked.
- [ ] **A running-app guard** (`Needs`) if the app holds the files open.
- [ ] **Short name** (fits 41 characters) and a sensible default: `On = $false` if the downside is a slow rebuild or it can't be undone.
- [ ] **A sandbox test** in `tests/selftest.ps1`: a fake folder under the sandbox that is removed (or kept, if unticked).
- [ ] **Docs:** a row in the table of [docs/SAFETY.md](docs/SAFETY.md) and in the README, and a line in [CHANGELOG.md](CHANGELOG.md).
- [ ] **Screenshots:** if the Disk screen changes, re-run `tools/Render-Screenshots.ps1`.

Use the **New cleanup category** issue form to discuss it first; maintainers will help you check the path.

### Or: an app cleaner (winapp2 rule)

Cleaning one app's cache is usually a [winapp2](https://github.com/MoscaDotTo/Winapp2) rule rather than a new category. `data/Winapp2.ini` is a copy of the Winapp2 project's database (CC BY-SA 4.0): send new or fixed rules **upstream**, so every winapp2 tool benefits, and test them locally in `%LOCALAPPDATA%\RetroBoost\custom\*.ini` (APP CLEAN reads that folder after the built-in file). Changes to how rules are *run* (the engine and its guards) belong here, with a sandbox test.

### Or: a tweak

One `[section]` in `data/WinRules.ini` (the header of that file documents every key). Checklist: a plain-words `Description`, the Windows default in `DefaultValue` (or `<deletevalue>`) so it can be undone, `Restart=explorer|system` if it only shows after a restart, `OsVersion` if it applies to one Windows version only, and a note in the PR of how you checked the value on a real PC. The catalogue comes from FluentCleaner: corrections are worth sending [upstream](https://github.com/builtbybel/FluentCleaner) too.

## Code style

- PowerShell 7, 4-space indent, no aliases in scripts (`ForEach-Object`, not `%`).
- Comment *why*, not *what*. Mark deliberate shortcuts with `# ponytail:` and say what the limit is.
- Watch the PowerShell traps listed in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#powershell-pitfalls-we-have-already-hit): case-insensitive variable names and dynamic scoping, `@()` flattening, `if`-expressions that unroll collections.
- Keep UI text within the grid (78 columns, 25 rows). `-Screenshot all` makes overflow obvious.
- Files: LF line endings for `.ps1`/`.md`, CRLF for `.cmd` (`.gitattributes` handles it).

## Testing

- `tests/selftest.ps1` must pass locally; CI runs it on Windows for every pull request.
- Never test deletions against real folders. Use `-Sandbox` (see ARCHITECTURE) or `-DryRun`.
- Fixed a bug? Add a check that would have caught it.

## Pull requests

1. Fork, create a branch (`fix/...`, `feat/...`, `docs/...`).
2. Keep it small and focused; one idea per PR.
3. Fill in the PR template: what changed, why, how you tested.
4. Be patient and kind: reviews are by volunteers. Maintainers may squash-merge.

Commit messages: short imperative subject (`Add Firefox cache category`), details in the body if needed.

## Reporting bugs

Use the **Bug report** form. Include your Windows version, terminal, `$PSVersionTable.PSVersion`, and what the plan screen showed (remove personal paths from logs). **If RetroBoost deleted or stopped something it shouldn't have, say so in the title:** that is the highest-priority bug there is. For security-sensitive reports, see [SECURITY.md](SECURITY.md).

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE). The rule files in `data/` keep their own licenses (see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)): changes to `Winapp2.ini` are shared under CC BY-SA 4.0. Contributors are thanked in the release notes.
