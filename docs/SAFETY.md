# Safety model

RetroBoost deletes files, writes Windows settings, uninstalls apps and stops programs. That is only acceptable if it is predictable, so these are the rules the code follows and the reasons behind them. If you find a case where the code breaks a rule, please [open an issue](https://github.com/DevDataAnalyst/RetroBoost/issues/new/choose): it is the highest-priority kind of bug.

## Principles

1. **Regenerable data by default.** BOOST and DISK CLEAN only remove data that apps or Windows rebuild by themselves. APP CLEAN offers more (history, cookies, recent-file lists), but those rules start **unticked**: you choose them.
2. **Guards beat rules.** Whatever a rule file says, your personal folders and the Windows folder are never touched (see below).
3. **User level by default, admin optional.** RetroBoost never asks for elevation. Started as administrator, it unlocks the `[A]` tweaks and machine-wide entries that rules name; nothing else changes.
4. **Plan before action.** Cleaning, tweaking, uninstalling and stopping show a plan and wait for ENTER. The BOOST confirmation can be switched off in Settings; the one-click launcher uses a countdown instead.
5. **Reversible where possible, honest where not.** Tweaks can be undone. Deleted files do **not** go to the Recycle Bin and RetroBoost cannot undo an uninstall: the plan screen says so.
6. **Never fight a running app.** Caches of a running browser or VS Code are skipped, browser rules in APP CLEAN wait for the browser to close, and files in use are skipped. The result screen says what was skipped and why.
7. **Say what happened.** The result screen and the log list what was cleaned, set, uninstalled, stopped, left running or skipped.

## What each DISK CLEAN category touches

| Category | Location | Rule |
|---|---|---|
| User temp files | `%TEMP%` | files older than 1 day only; the top-level `claude` folder is skipped (an author's choice, see below); locked files are skipped silently |
| Package caches | `%LOCALAPPDATA%\npm-cache`, `uv\cache`, `pip\cache`, `Yarn\Cache`, `NuGet\v3-cache`; `%USERPROFILE%\.bun\install\cache` | whole folders; only caches, never installed tools (`Yarn\bin`, `.bun\install\global` and `uv-receipt.json` stay) |
| Browser caches | Brave, Chrome and Edge: `User Data\*\Cache`, `Code Cache`, `GPUCache` | skipped while the browser runs; profiles, logins, history and bookmarks are never touched |
| App updater downloads | `%LOCALAPPDATA%\*-updater` (folders) | installer copies left by auto-updaters |
| VS Code leftovers | `%APPDATA%\Code\CachedExtensionVSIXs`; hidden `.<guid>` folders in `%USERPROFILE%\.vscode\extensions` | skipped while VS Code runs; installed extensions stay |
| Crash dumps and reports | `%LOCALAPPDATA%\CrashDumps`, `%LOCALAPPDATA%\Microsoft\Windows\WER` | diagnostic leftovers |
| GPU shader caches | `D3DSCache`, `NVIDIA\DXCache`, `NVIDIA\GLCache`, `AMD\DxCache` under `%LOCALAPPDATA%` | **unticked by default**: games rebuild them, with a one-time stutter |
| Recycle Bin | drive C: | **unticked by default**: `Clear-RecycleBin`, cannot be undone |

## APP CLEAN (winapp2 rules)

APP CLEAN runs the rules of `data/Winapp2.ini` (and your own `custom\*.ini`) the way FluentCleaner does: a rule is listed only if its app is detected (`Detect`, `DetectFile`, `SpecialDetect`), and it deletes the files its `FileKey` lines match (with `RECURSE` and `REMOVESELF`) minus its `ExcludeKey` lines, plus the registry entries its `RegKey` lines name. On top of that, RetroBoost applies guards no rule can get past (`Test-Never` and `Test-Keep` in [`src/retroboost.ps1`](../src/retroboost.ps1)):

| Guard | Why |
|---|---|
| Documents, Desktop, Downloads, Pictures, Music, Videos and OneDrive folders are never touched | your files |
| The **whole Windows folder** is never touched | Windows cleans itself (`W` on DISK CLEAN); a rule can't reach `System32`, `WinSxS`, logs or drivers |
| `Program Files\WindowsApps` and `ProgramData\Package Cache` are never touched | Store app installs; installer caches needed to repair and uninstall |
| Files in `%TEMP%` younger than a day stay; `%TEMP%\claude` stays | same rule as DISK CLEAN: fresh temp files may be in use |
| `\IndexedDB\chrome-extension_` stays | browser-extension databases, such as password managers (a FluentCleaner rule) |
| Files that can't be opened for deletion are skipped and not counted | in use without share-delete, or need admin: never fought, never over-reported |
| Junctions and symbolic links are never followed | no loops, no escapes into other folders |
| `REMOVESELF` never removes a drive root or a known folder (`%TEMP%`, `%APPDATA%`…) | it only prunes empty folders a rule emptied |
| Registry: never a hive or a top-level key; machine-wide keys only when running as administrator | a rule names specific entries (recent-file lists, telemetry values); no orphan scanning |
| Your `"exclude"` lines in `config.json` | winapp2 syntax (`PATH\|dir\`, `FILE\|dir\\|name`, `REG\|key`); apply to every rule |

**Default ticks.** A rule starts ticked only if winapp2 ticks it by default, it carries no warning, and its name says cache, temp, log, crash, dump, thumbnail or telemetry (shader caches excepted, like DISK CLEAN). Everything else (history, cookies, sessions, saved passwords, autofill, recent-file lists, backups, unsaved files) is listed but unticked. Your ticks are saved in `config.json` (`appClean`); `A` restores the safe set.

**BOOST** runs APP CLEAN only if you switch on SETTINGS → BOOST+APP CLEAN, and then only your ticks.

### The cookie keep-list

- **No list, winapp2's behaviour.** A browser's cookie cleaner deletes its cookie database, as the rule says. These rules start unticked, and the plan screen warns that every site will sign you out.
- **With a list, an edit instead of a delete.** For a cookie database (`Cookies` in Chromium-family browsers, `cookies.sqlite` in Firefox-family ones) RetroBoost runs one `DELETE` inside a transaction: every cookie whose host is not a kept site or a subdomain of one goes (`github.com` keeps `.github.com` and `api.github.com`, not `notgithub.com`), then the file is compacted. Its journal and *Device Bound Sessions* files are left alone, so a kept login isn't invalidated.
- **Never worse than doing nothing.** If the database can't be opened or edited (the browser holds it, it isn't SQLite, the table isn't there), RetroBoost leaves the file whole and logs why. It never falls back to deleting it. Any error before the commit rolls the transaction back.
- **Read-only browsing.** The COOKIES screen opens each database read-only and reads only site names, never cookie values. Nothing leaves the PC.
- **Where it looks.** The databases are found through the detected browsers' own winapp2 cookie rules, and edited with the SQLite that ships with Windows (`winsqlite3.dll`): no extra binaries.
- Sites are listed by their last two labels (three after `co.uk`-style endings), so a kept site always keeps at least what you picked, never less.

## TWEAKS (registry settings)

- The catalogue is `data/WinRules.ini`. Each setting names its registry values, the **recommended** value and the **Windows default**. A setting is listed only if it fits your Windows version (`OsVersion`) and, where it says so, the program it changes is installed (`RequiresKey`).
- **Apply** writes the recommended values; **undo** (`[u]`) writes the defaults. All values of a setting are checked for type before anything is written, and every value is **read back** afterwards: a setting counts as done only if Windows kept it. A failed setting is reported; values written before the failure are not rolled back (the log lists them).
- Settings under `HKLM`, `HKCR` or `\Policies\` change every account, so Windows requires an administrator: RetroBoost marks them `[A]` and won't tick them unless it runs elevated.
- A setting without a recorded default cannot be undone, and RetroBoost refuses to mark it for undo.
- Some settings show only after Explorer or Windows restarts; the result screen says which, and offers `X` to restart Explorer.

## UNINSTALL

- **Nothing is pre-ticked.** `A` ticks the *suggested* apps (put there to advertise or sell, per `data/AppRules.ini`); you still read the plan and press ENTER.
- **Protected, always:** Store packages Windows needs (anything signed `*_cw5n1h2txyewy`, the Store, App Installer, Windows Security, frameworks, runtimes, Edge), non-removable, framework and resource packages, the programs `AppRules.ini` marks as needed by Windows and the hardware (Visual C++, .NET, drivers…), and what RetroBoost runs in: PowerShell and Windows Terminal. Protected rows show `#` and can't be ticked; the uninstaller checks again before removing.
- **Store apps** are removed for your account with `Remove-AppxPackage` and can be reinstalled from the Microsoft Store.
- **Programs**: the silent ways first (the program's own quiet uninstaller, then `msiexec /x … /qn` for Windows Installer products), each with a 5-minute limit; then the program's own uninstaller window, which you finish yourself. RetroBoost never deletes a program's folder by hand.
- **Verified:** an uninstaller's exit code proves nothing, so success means Windows no longer lists the app.

## AUTO (`-Auto` and the schedule)

- `-Auto` runs BOOST's safe disk categories (and your APP CLEAN ticks, if BOOST+APP CLEAN is on) without a screen. It **never stops programs and never trims RAM**, because nobody is there to save their work.
- `-Shutdown` (only with `-Auto`) shuts Windows down **60 seconds** later; `shutdown /a` cancels.
- SETTINGS → AUTO-CLEAN creates a Task Scheduler task for your account (no admin), *RetroBoost AutoClean*, and removes it when set back to `OFF`. `-DryRun`, `-Demo` and the test hooks never create one.

## What it never touches

- The Windows folder, `Program Files\WindowsApps`, `ProgramData\Package Cache`, the page file, restore points.
- Your files: Documents, Pictures, Videos, Music, Desktop, Downloads, OneDrive.
- Protected programs and apps (see above), and RetroBoost's own process.

For Windows' own junk (Update cache, setup logs, previous installations) RetroBoost opens *Settings → System → Storage → Temporary files* and lets Windows do the work (`W` on the Disk screen).

## Process protection

A program can be put on the kill list, marked or stopped **only** if it is not protected. A program is protected when **any** of these is true (see `Test-Protected` in [`src/retroboost.ps1`](../src/retroboost.ps1)):

- its name is on the built-in list: Windows core (`System`, `smss`, `csrss`, `wininit`, `winlogon`, `services`, `lsass`, `svchost`, `dwm`, `explorer`, …), shell and input hosts, the console and terminals (`conhost`, `WindowsTerminal`, `cmd`, `powershell`, `pwsh`), Windows Defender and security-health processes, WSL and virtual-machine hosts, and a few third-party security and AI-assistant processes (`avp`, `avpui`, `claude`);
- its executable lives under the Windows folder;
- it runs in session 0 (Windows services);
- its path cannot be read (an elevated or system process).

Protected programs show as `PROTECTED` with a `#`, cannot be marked or added to the kill list, and are ignored even if they appear in `config.json` by hand. RetroBoost also never stops its own process. (The only exception is the explicit `X` on the TWEAKS result screen, which restarts Explorer when you ask.)

### Graceful first

For a program with a window, RetroBoost sends a normal close request and waits a few seconds, so the program can ask you to save. If a window is still open afterwards, RetroBoost **leaves that program alone** and reports "still open". Background helpers (no window) are ended directly. **Force** (`F`) is a separate, explicit action that warns about unsaved work.

## Dry-run, demo and logs

- `-DryRun`: every screen works; nothing is deleted, set, uninstalled, scheduled, trimmed or stopped; the log lines are prefixed `[DRY]`.
- `-Demo`: invented data; the real PC isn't read (the tweak catalogue file is, the registry isn't), no log or settings are written.
- Log: `%LOCALAPPDATA%\RetroBoost\boost.log` records each category or rule with its size, each cookie database edited (or left whole, and why), each setting applied or undone, each app removed or not, each program stopped, the RAM trim and every `-Auto` run.

## How it is tested

[`tests/selftest.ps1`](../tests/selftest.ps1) builds a sandbox (every cleaner location, `%WinDir%` and the personal folders are redirected into it) and a throwaway registry key, then checks that:

- a dry run leaves every file, registry value and program alone, reports what it *would* stop, and never offers `explorer` even if it is in the kill list;
- a real BOOST removes the caches, updater downloads, dumps and VSIX cache and the old temp file, **keeps** the recent temp file, the `claude` folder and the unticked shader cache, and stops only the fake program;
- the winapp2 engine removes what its test rule names (recursing), keeps the `ExcludeKey` file, the non-matching file, a file **in use**, the Documents file and the **Windows-folder** file, leaves an unticked rule alone, ignores a rule whose app isn't installed, and removes the named registry key;
- a real SQLite cookie database in a fake Chrome profile is listed by site on the COOKIES screen, a site kept with `SPACE` is saved, a dry run changes no cookie, a real run keeps the kept site and its subdomains and removes the rest (a look-alike domain too), keeps the database and its session file, and without a keep-list the whole database is deleted as the rule says;
- a test tweak is applied (two values, read back) and then undone (default written back, extra value deleted), and a dry run writes nothing;
- a throwaway program entry is really uninstalled by its silent uninstaller (and a dry run leaves it); under `-Sandbox` only programs named `rbtest*` are listed, so no real app is ever offered;
- `-Auto` cleans, logs and never stops a program;
- demo mode shows invented programs and apps, refuses to tick a protected app, writes nothing, and all ten screens render without errors.

CI runs it on Windows for every push and pull request. A new cleanup category or engine change must come with a sandbox test (see [CONTRIBUTING](../CONTRIBUTING.md#add-a-cleanup-category)).

## Author's choices you may want to change

A few defaults reflect the author's setup and are good candidates for becoming configurable ([roadmap](ROADMAP.md)):

- `claude` is on the protected list and the temp cleaners skip `%TEMP%\claude`, so an AI coding assistant's working files aren't pulled out from under it.
- DISK CLEAN's browser list is Brave, Chrome and Edge (APP CLEAN covers many more).
- The safe default ticks of APP CLEAN come from a keyword list (a `ponytail:` note in the code); a curated list would be stricter.

## Limitations

- RetroBoost is an unsigned script; cautious security tools may flag it.
- The RAM trim only trims working sets; it cannot make Windows keep memory free.
- Locked files are skipped, so a category can free less than its size says.
- APP CLEAN is only as good as its rules: a winapp2 rule could name something you value. That is why only cache, temp and log rules start ticked, why the guards above exist, and why the selected rule's paths are shown on screen.

## Reporting a problem

See [SECURITY.md](../SECURITY.md). For "it touched something it shouldn't have", include the log, your Windows version and what the plan screen showed.
