# Architecture

A guide for contributors. RetroBoost is deliberately **one readable PowerShell 7 script** ([`src/retroboost.ps1`](../src/retroboost.ps1), about 1,500 lines) plus three rule files it reads as data. If it outgrows that, splitting it into modules is a welcome proposal; open an issue first.

## Repository map

```text
RetroBoost.cmd              double-click launcher (checks for pwsh, sets UTF-8, runs src\retroboost.ps1)
RetroBoost-OneClick.cmd     same, with -Boost -Yes
src/retroboost.ps1          the app
data/Winapp2.ini            APP CLEAN rules (Winapp2 project, CC BY-SA 4.0)
data/WinRules.ini           TWEAKS catalogue (FluentCleaner, MIT)
data/AppRules.ini           UNINSTALL classification (FluentCleaner, MIT)
tests/selftest.ps1          sandbox test: real deletes, registry writes, an uninstall and a kill, on throwaway targets only
tools/Render-Screenshots.ps1  paints README screenshots from the app's own screen buffer
docs/                       guides, roadmap, release notes, screenshots
THIRD-PARTY-NOTICES.md      where the rule files and the ported engines come from, and their licenses
.github/                    issue forms, PR template, CI workflow
```

## How the script is organised

Top to bottom, in one file:

1. **Parameters and state**: `-Boost -Yes -DryRun -Demo -Auto -Shutdown -Theme -ConfigDir`, plus test hooks.
2. **Settings and log**: `%LOCALAPPDATA%\RetroBoost\config.json` (theme, sound, confirm, kill list, `boostApps`, `schedule`, `appClean`, `exclude`) and `boost.log`.
3. **Helpers**: sizes, formatting, word wrap, system numbers (`Get-Sys`), safe path measuring (`Get-PathBytes`).
4. **Process protection**: `$protectedNames` and `Test-Protected`.
5. **Disk categories**: the `$cats` list, `Scan-Disk` (measure), `Invoke-Clean` (delete; hands APP CLEAN rules to `Clean-Rule`).
6. **Processes and RAM**: `Load-Procs`, `Get-KillTargets`, `Stop-App`, `Invoke-RamTrim`; `Use-Native` compiles the few Windows calls (`EmptyWorkingSet`, `SendMessageTimeout`, a `CreateFileW` delete-access probe).
7. **APP CLEAN engine** (port of FluentCleaner's `Winapp2Parser`, `DetectionService`, `PathExpander`, `CleaningService`): `Read-Rules` → `Test-Rule` → `Scan-Rule` → `Clean-Rule`, with the guards `Test-Never` and `Test-Keep`.
8. **TWEAKS engine** (port of `TweakDatabase`, `RegistryService`, `Scanner`, `Applier`): `Read-Tweaks`, `Test-TweakVal`, `Set-TweakVal`, `Invoke-Tweak`.
9. **UNINSTALL engine** (port of `AppRules`, `PackageService`, `ProgramService`): `Read-AppRules`, `Get-Safety`, `Load-Apps`, `Remove-App`.
10. **AUTO**: `Invoke-Auto` (the windowless run) and `Set-Schedule` (Task Scheduler).
11. **Screen buffer and themes**: a 78×25 character grid ("video RAM").
12. **Screens**: one `Draw-<name>` and one `Key-<name>` function per screen; the three list screens share `Set-Items`, `Move-Sel`, `Draw-List` and `Put-Info`.
13. **Plan, run, boost**: `Show-Plan`, `Start-Run`, `Start-Boost`.
14. **Terminal and main loop**: alternate screen, splash, `Read-Key`, the loop.

### The screen buffer

Nothing writes to the console directly while drawing. `Put row col text style` writes into two arrays (`$cellC` characters, `$cellS` style ids). `Show-Buf` then turns the whole grid into **one** string of ANSI escape codes and writes it once, so there is no flicker. The same buffer is what tests and the screenshot tool read. This is why the UI is easy to test without a terminal.

Styles are indices into a theme table (`$themes`, 256-colour `fg;bg[;bold]`). Adding a theme is one hashtable.

### The main loop

```text
Redraw → Read-Key (2.5 s tick) → Key-<screen> handler → repeat
```

`$app.screen` names the current screen; `Redraw` calls `Draw-<screen>`; the key goes to `Key-<screen>`. Screens: `main disk appclean ram procs tweaks uninst settings help`, plus `run` and `result`.

### One pipeline for every action

Every action is a hashtable handed to `Start-Run`:

```powershell
Start-Run @{ Title = 'APP CLEAN'; Clean = $rules; Ask = $true; Skipped = (Get-Skipped $app.rules) }
Start-Run @{ Title = 'TWEAKS'; Tweak = $marked; Ask = $true }
Start-Run @{ Title = 'BOOST'; Clean = $sel; Kill = $names; Ram = $true; Ask = $true; Skipped = ... }
```

Keys: `Title`, `Clean` (DISK categories and APP CLEAN rules), `Kill`, `Ram`, `Force`, `Tweak`, `Uninstall`, `Ask`, `Skipped`. `Show-Plan` draws the plan from it, `Start-Run` runs each part on the `run` screen and fills `$app.res`, and `Draw-result` shows only the sections that ran. Read the lists as `$job['Clean']` (see the pitfalls).

### The list screens

APP CLEAN, TWEAKS and UNINSTALL show one scrolling list: `Set-Items` turns (group name, members) pairs into header rows followed by their members, `Move-Sel` moves the selection (`← →` jump between headers), `Draw-List` draws rows 5–17 with a per-screen formatter, and `Put-Info` fills rows 19–21 with details of the selected row. `SPACE` on a header row acts on the whole group.

### Safety plumbing

Every destructive function checks `$script:Dry` (dry-run) or `$Demo`. The code that deletes files is `Invoke-Clean` and `Clean-Rule`; the code that writes registry values is `Set-TweakVal` (and `Clean-Rule` for rule `RegKey`s); the code that uninstalls is `Remove-App`; the code that stops programs is `Stop-App`. Keep it that way: it makes review easy. The guards for APP CLEAN live in `Test-Never` (folders no rule may touch) and `Test-Keep` (per-file checks); a rule can never bypass them.

## Test hooks

These switches exist so the app can be tested and photographed without a keyboard:

| Hook | Purpose | Example |
|---|---|---|
| `-Sandbox <dir>` | replaces every real location with a folder inside `<dir>` (caches, `%WinDir%`, the personal folders, every winapp2 variable), reads the rule files from `<dir>\data`, skips the Recycle Bin and the running-browser check, restricts the RAM trim to processes named `rbtest*` and UNINSTALL to programs named `rbtest*` (no Store apps) | `-Sandbox $env:TEMP\rb -DryRun` |
| `-Keys a,b,c` | feeds scripted keystrokes instead of the keyboard (`enter`, `esc`, `space`, `up`, `down`, `left`, `right`, `pgdn`, `end`, letters); output is plain-text frames; never creates a scheduled task | `-Keys b,enter` |
| `-Screenshot <screen>` | prints one screen as plain text and exits (`main disk appclean ram procs tweaks uninst settings help all`) | `-Screenshot all` |
| `-Dump <file>` | with the two above: also writes each frame as JSON (characters, style ids, palette) | `-Demo -Screenshot main -Dump main.json` |
| `-Demo` | invented system numbers, categories, rules, tweak states, apps and programs | `-Demo -Keys u,a,enter,enter` |

Try the app headlessly:

```powershell
pwsh -File src/retroboost.ps1 -Demo -Screenshot all        # every screen as text
pwsh -File src/retroboost.ps1 -Demo -Keys b,enter          # a whole BOOST, frame by frame
pwsh -File src/retroboost.ps1 -DryRun -Keys a,s            # APP CLEAN on your PC: scan only, nothing deleted
pwsh -File tests/selftest.ps1                              # the safety test
pwsh -File tools/Render-Screenshots.ps1                    # regenerate docs/screenshots/*.png
```

## Add a cleanup category

A category is one hashtable in `$cats`:

```powershell
@{ Id = 'exampleapp'; Name = 'ExampleApp cache'; On = $true
   Needs = { if (Get-Process ExampleApp -ErrorAction SilentlyContinue) { 'close ExampleApp' } }   # optional: reason it can't run now
   Paths = { "$pLocal\ExampleApp\Cache" } }                                                       # paths or items to measure and remove
```

- `Paths` returns strings or file-system items. Use `$pLocal`, `$pRoam`, `$pTemp`, `$pHome`; they are redirected into the sandbox under test.
- `Kind = 'age'` deletes only files older than a day (see `temp`); `Kind = 'recycle'` is special-cased.
- Keep the name **short** (it must fit the Disk screen: 41 characters).
- Add a fake folder for it to `tests/selftest.ps1` and assert it is removed (or kept, if unticked).
- Add a row to the table in [SAFETY.md](SAFETY.md) and the README.

Most app-specific cleaning belongs in a winapp2 rule instead (APP CLEAN): improve the [Winapp2 project](https://github.com/MoscaDotTo/Winapp2), or ship your own rule in `%LOCALAPPDATA%\RetroBoost\custom\*.ini`. The full checklist is in [CONTRIBUTING.md](../CONTRIBUTING.md#add-a-cleanup-category).

## Add a tweak

One `[section]` in `data/WinRules.ini`; the file's header documents every key (`Category`, `Description`, `Path`, `ValueName`, `ValueType`, `RecommendedValue`, `DefaultValue`, `Restart`, `OsVersion`, `RequiresKey`, `Group`, `DefaultSelected`). Always record the Windows default (`DefaultValue`, or `<deletevalue>` if the value doesn't exist by default) so the setting can be undone. Paths under `HKLM`, `HKCR` or `\Policies\` are marked `[A]` automatically.

## Add a screen

1. Write `Draw-<name>` (start with `Draw-Chrome '<hint bar text>'`, then `Box`, `Put`, `Gauge`, or `Draw-List` for a list).
2. Write `Key-<name> $k` (handle `UP`, `DOWN`, `ENTER`, `ESC`, letters; call `Open-Screen 'main'` to go back).
3. Add it to `Open-Screen` if it needs data loaded, to the menu, and to the `-Screenshot all` list and the screenshot tool.

## PowerShell pitfalls we have already hit

Save yourself an evening:

- **Variable names are case-insensitive and callees see their caller's variables.** A local `$rows` shadowed the global `$ROWS` for every function it called. Use distinct names (`$opts`, `$items`).
- **Newline-separated `@( @(…) @(…) )` flattens.** A line holding a single array needs a leading comma: `, @(…)`. A line holding several (`@(…), @(…)`) must **not** have one, or its first array gets wrapped twice.
- **`$x = if (…) { <collection> }` unrolls the collection.** Assign directly (this broke the key queue).
- **`@($null).Count` is 1.** Count a list that may be `$null` with `[int]$x.Count`, or drop nulls first (`Arr` in the script).
- **`$hashtable.Remove` is a method** when the key is missing, not `$null`. Read optional keys as `$job['Remove']`.
- **`'text'.IndexOf('x', 'OrdinalIgnoreCase')` picks the `(string, int startIndex)` overload** and throws. Pass `[StringComparison]::OrdinalIgnoreCase`. (`StartsWith`/`EndsWith` have no such overload and are fine.) This one silently emptied every APP CLEAN scan until the self-test caught it.
- **`Group-Object` sorts its groups.** Use `Group-Keep` to keep a sorted list's order.
- **A child process inherits the console.** Uninstallers and other tools must get redirected (and drained) standard streams, or their output lands on the retro screen.
- **`pwsh -File … -Param a,b` passes `a,b` as one string.** Split it yourself.
- **`$a = [long]; [Math]::Max(1, $a)`** picks the `int` overload and fails on large values; use `1L`.
- **A drive name alone (`C:`) means the current folder of that drive**, not its root. Never `TrimEnd('\')` a root before using it as a path.

## Rendering screenshots

`tools/Render-Screenshots.ps1` runs the app with `-Demo -Dump`, reads the JSON frames and paints them with `System.Drawing` (box-drawing and block characters are drawn as rectangles, so they join perfectly regardless of the font). Windows only. Re-run it after any UI change and commit the PNGs.
