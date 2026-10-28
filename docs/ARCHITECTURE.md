# Architecture

A guide for contributors. RetroBoost is deliberately **one readable PowerShell 7 script** ([`src/retroboost.ps1`](../src/retroboost.ps1), about 800 lines). If it outgrows that, splitting it into modules is a welcome proposal; open an issue first.

## Repository map

```text
RetroBoost.cmd              double-click launcher (checks for pwsh, sets UTF-8, runs src\retroboost.ps1)
RetroBoost-OneClick.cmd     same, with -Boost -Yes
src/retroboost.ps1          the app
tests/selftest.ps1          sandbox test: real deletes and a real kill, on fake targets only
tools/Render-Screenshots.ps1  paints README screenshots from the app's own screen buffer
docs/                       guides, roadmap, release notes, screenshots
.github/                    issue forms, PR template, CI workflow
```

## How the script is organised

Top to bottom, in one file:

1. **Parameters and state**: `-Boost -Yes -DryRun -Demo -Theme -ConfigDir`, plus test hooks.
2. **Settings and log**: `%LOCALAPPDATA%\RetroBoost\config.json` (theme, sound, confirm, kill list) and `boost.log`.
3. **Helpers**: sizes, formatting, system numbers (`Get-Sys`), safe path measuring (`Get-PathBytes`).
4. **Process protection**: `$protectedNames` and `Test-Protected`.
5. **Disk categories**: the `$cats` list, `Scan-Disk` (measure), `Invoke-Clean` (delete).
6. **Processes and RAM**: `Load-Procs`, `Get-KillTargets`, `Stop-App`, `Invoke-RamTrim`.
7. **Screen buffer and themes**: a 78×25 character grid ("video RAM").
8. **Screens**: one `Draw-<name>` and one `Key-<name>` function per screen.
9. **Plan, run, boost**: `Show-Plan`, `Start-Run`, `Start-Boost`.
10. **Terminal and main loop**: alternate screen, splash, `Read-Key`, the loop.

### The screen buffer

Nothing writes to the console directly while drawing. `Put row col text style` writes into two arrays (`$cellC` characters, `$cellS` style ids). `Show-Buf` then turns the whole grid into **one** string of ANSI escape codes and writes it once, so there is no flicker. The same buffer is what tests and the screenshot tool read. This is why the UI is easy to test without a terminal.

Styles are indices into a theme table (`$themes`, 256-colour `fg;bg[;bold]`). Adding a theme is one hashtable.

### The main loop

```text
Redraw → Read-Key (2.5 s tick) → Key-<screen> handler → repeat
```

`$app.screen` names the current screen; `Redraw` calls `Draw-<screen>`; the key goes to `Key-<screen>`. Actions (`Start-Run`) switch to the `run` screen, draw progress themselves, then switch to `result`.

### Safety plumbing

Every destructive function checks `$script:Dry` (dry-run) or `$Demo`. The only code that deletes is `Invoke-Clean`; the only code that stops programs is `Stop-App`. Keep it that way: it makes review easy.

## Test hooks

These switches exist so the app can be tested and photographed without a keyboard:

| Hook | Purpose | Example |
|---|---|---|
| `-Sandbox <dir>` | replaces every real cache location with a folder inside `<dir>`, skips the Recycle Bin, restricts the RAM trim to processes named `rbtest*` | `-Sandbox $env:TEMP\rb -DryRun` |
| `-Keys a,b,c` | feeds scripted keystrokes instead of the keyboard (`enter`, `esc`, `space`, `up`, `down`, letters); output is plain-text frames | `-Keys b,enter` |
| `-Screenshot <screen>` | prints one screen as plain text and exits (`main disk ram procs settings help all`) | `-Screenshot all` |
| `-Dump <file>` | with the two above: also writes each frame as JSON (characters, style ids, palette) | `-Demo -Screenshot main -Dump main.json` |
| `-Demo` | invented system numbers, categories and programs | `-Demo -Keys b,enter` |

Try the app headlessly:

```powershell
pwsh -File src/retroboost.ps1 -Demo -Screenshot all        # every screen as text
pwsh -File src/retroboost.ps1 -Demo -Keys b,enter          # a whole BOOST, frame by frame
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

The full checklist is in [CONTRIBUTING.md](../CONTRIBUTING.md#add-a-cleanup-category).

## Add a screen

1. Write `Draw-<name>` (start with `Draw-Chrome '<hint bar text>'`, then `Box`, `Put`, `Gauge`).
2. Write `Key-<name> $k` (handle `UP`, `DOWN`, `ENTER`, `ESC`, letters; call `Open-Screen 'main'` to go back).
3. Add it to `Open-Screen` if it needs data loaded, and to the `-Screenshot all` list and the screenshot tool.

## PowerShell pitfalls we have already hit

Save yourself an evening:

- **Variable names are case-insensitive and callees see their caller's variables.** A local `$rows` shadowed the global `$ROWS` for every function it called. Use distinct names (`$opts`, `$items`).
- **Newline-separated `@( @(…) @(…) )` flattens.** Write `@( ,@(…) ,@(…) )` or put commas between the items.
- **`$x = if (…) { <collection> }` unrolls the collection.** Assign directly (this broke the key queue).
- **`pwsh -File … -Param a,b` passes `a,b` as one string.** Split it yourself.
- **`$a = [long]; [Math]::Max(1, $a)`** picks the `int` overload and fails on large values; use `1L`.
- **Parameter names that match globals** (`$h`, `$w`) are fine, but remember the first point.

## Rendering screenshots

`tools/Render-Screenshots.ps1` runs the app with `-Demo -Dump`, reads the JSON frames and paints them with `System.Drawing` (box-drawing and block characters are drawn as rectangles, so they join perfectly regardless of the font). Windows only. Re-run it after any UI change and commit the PNGs.
