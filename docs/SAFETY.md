# Safety model

RetroBoost deletes files and stops programs. That is only acceptable if it is predictable, so these are the rules the code follows and the reasons behind them. If you find a case where the code breaks a rule, please [open an issue](https://github.com/DevDataAnalyst/RetroBoost/issues/new/choose): it is the highest-priority kind of bug.

## Principles

1. **Only regenerable data.** A category exists only if the app or Windows rebuilds the data by itself. Documents, photos, downloads and desktop files are never candidates.
2. **User level, no admin.** RetroBoost never asks for elevation. Anything that needs admin rights is out of scope (see the [roadmap](ROADMAP.md) for a guarded opt-in idea).
3. **Plan before action.** Cleaning and stopping show a plan and wait for ENTER. The confirmation can be switched off in Settings; the one-click launcher uses a countdown instead.
4. **Reversible where possible, honest where not.** Deleted files do **not** go to the Recycle Bin. That is why only regenerable categories exist, and why the Recycle Bin category (permanent) starts unticked.
5. **Never fight a running app.** Caches of a running browser or VS Code are skipped, and the result screen says so.
6. **Say what happened.** The result screen and the log list what was cleaned, stopped, left running or skipped.

## What each category touches

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

## What it never touches

- Windows itself: `WinSxS`, `System32`, `Installer`, `Package Cache`, the driver store, `WindowsApps`, the page file, restore points.
- Your files: Documents, Pictures, Videos, Music, Desktop, Downloads.
- Anything outside your user profile and the Recycle Bin of C:.
- Other drives.

For Windows' own junk (Update cache, setup logs, previous installations) RetroBoost opens *Settings → System → Storage → Temporary files* and lets Windows do the work (`W` on the Disk screen).

## Process protection

A program can be put on the kill list, marked or stopped **only** if it is not protected. A program is protected when **any** of these is true (see `Test-Protected` in [`src/retroboost.ps1`](../src/retroboost.ps1)):

- its name is on the built-in list: Windows core (`System`, `smss`, `csrss`, `wininit`, `winlogon`, `services`, `lsass`, `svchost`, `dwm`, `explorer`, …), shell and input hosts, the console and terminals (`conhost`, `WindowsTerminal`, `cmd`, `powershell`, `pwsh`), Windows Defender and security-health processes, WSL and virtual-machine hosts, and a few third-party security and AI-assistant processes (`avp`, `avpui`, `claude`);
- its executable lives under the Windows folder;
- it runs in session 0 (Windows services);
- its path cannot be read (an elevated or system process).

Protected programs show as `PROTECTED` with a `#`, cannot be marked or added to the kill list, and are ignored even if they appear in `config.json` by hand. RetroBoost also never stops its own process.

### Graceful first

For a program with a window, RetroBoost sends a normal close request and waits a few seconds, so the program can ask you to save. If a window is still open afterwards, RetroBoost **leaves that program alone** and reports "still open". Background helpers (no window) are ended directly. **Force** (`F`) is a separate, explicit action that warns about unsaved work.

## Dry-run, demo and logs

- `-DryRun`: every screen works, nothing is deleted, trimmed or stopped; the log lines are prefixed `[DRY]`.
- `-Demo`: invented data; the real PC isn't read, no log or settings are written.
- Log: `%LOCALAPPDATA%\RetroBoost\boost.log` records each category with its size, each program stopped, and the RAM trim.

## How it is tested

[`tests/selftest.ps1`](../tests/selftest.ps1) creates a sandbox with fake caches, a fake old temp file, a recent temp file, a `claude` temp folder, a shader cache and a harmless `ping.exe` copy named like an unwanted program, then checks that:

- a dry run leaves every file and the program alone, reports what it *would* stop, and never offers `explorer` even if it is in the kill list;
- a real BOOST removes the caches, updater downloads, dumps and VSIX cache, removes the old temp file, **keeps** the recent one, the `claude` folder and the unticked shader cache, and stops only the fake program;
- demo mode shows invented programs, writes nothing, and all screens render without errors.

CI runs it on Windows for every push and pull request. A new cleanup category must come with a sandbox test (see [CONTRIBUTING](../CONTRIBUTING.md#add-a-cleanup-category)).

## Author's choices you may want to change

A few defaults reflect the author's setup and are good candidates for becoming configurable ([roadmap](ROADMAP.md)):

- `claude` is on the protected list and the temp cleaner skips `%TEMP%\claude`, so an AI coding assistant's working files aren't pulled out from under it.
- The browser list is Brave, Chrome and Edge.

## Limitations

- RetroBoost is an unsigned script; cautious security tools may flag it.
- The RAM trim only trims working sets; it cannot make Windows keep memory free.
- Locked files are skipped, so a category can free less than its size says.

## Reporting a problem

See [SECURITY.md](../SECURITY.md). For "it touched something it shouldn't have", include the log, your Windows version and what the plan screen showed.
