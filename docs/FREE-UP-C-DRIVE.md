# Free up your C: drive: a clear plan

> **Goal:** get a nearly full C: drive back to a healthy level in about 30 minutes, safely, starting with the steps that give the most space for the least risk.

This works for any Windows 10 or 11 PC. Step 2 is automated by [RetroBoost](../README.md); the other steps use tools that are already built into Windows. Menu names differ slightly between Windows versions.

## How much free space is "enough"?

Windows needs working room: feature updates, the page file, temporary files and the search index all grow when space is tight, and updates can fail outright on a very full drive. A practical target is **at least 15–20% free, and never less than about 10 GB**. On a 256 GB drive that means keeping roughly 40–50 GB free.

## The plan at a glance

| # | Step | Time | Typical gain¹ | Risk | Tool |
|---|------|------|---------------|------|------|
| 1 | Measure | 1 min | n/a | none | RetroBoost gauge, or *Settings → System → Storage* |
| 2 | Clear the safe junk | 2 min | 0.5–10 GB | very low | RetroBoost **BOOST NOW** |
| 3 | Let Windows clean itself | 5 min | 1–25 GB | low | *Settings → System → Storage → Temporary files* |
| 4 | Uninstall what you don't use | 5 min | 2–50+ GB | low | *Settings → Apps → Installed apps* |
| 5 | Hunt big files | 10 min | varies | low if you look first | File Explorer search, or a disk-usage visualizer |
| 6 | Move, don't delete | 10 min | 5–100+ GB moved | low | OneDrive, library locations, game launchers |
| 7 | Keep it clean | 2 min, once | prevents the next crunch | none | Storage Sense, a monthly RetroBoost |
| + | Developer extras | 10 min | 5–50+ GB | medium | Docker, WSL, SDKs, `node_modules` |
| + | Advanced system features | 5 min | 2–20 GB | **higher: read first** | hibernation, restore points |

¹ *Typical gains are rough ranges from common situations, not promises. A freshly cleaned PC may have little to gain; a developer PC or a gaming PC may have far more.*

---

## 1. Measure (1 minute)

Know where you start, so you can see what each step bought you.

- Open RetroBoost: the **DISK C:** gauge shows used vs. total and turns **red above 85%**.
- Or open **Settings → System → Storage**. Windows breaks usage down into *Apps & features*, *Temporary files*, *Documents*, *Pictures* and so on. Click a category to see what is in it.

Write down the free space in GB. You'll compare at the end.

## 2. Clear the safe junk (2 minutes): RetroBoost

Run **BOOST NOW** (or *DISK CLEAN* if you want to tick things yourself). It removes only files that come back by themselves:

- temp files older than a day,
- npm, pip, uv, Yarn, bun and NuGet caches,
- browser caches (close the browser first),
- app installer downloads (`*-updater` folders),
- VS Code leftovers and crash dumps.

Close your browser and VS Code first so those categories can run. The result screen shows before → after.

## 3. Let Windows clean itself (5 minutes)

Windows knows its own system files best, so let it remove them.

Open **Settings → System → Storage → Temporary files** (RetroBoost: *DISK CLEAN* → `W`). Windows lists what it can remove. Typical entries, from safest to "think first":

| Entry | What it is | Notes |
|---|---|---|
| **Windows Update Cleanup** | superseded update files | safe; can be several GB |
| **Windows upgrade log files** | logs from past feature updates | safe |
| **Delivery Optimization Files** | update files cached to share with other PCs | safe; can be turned off in Windows Update settings |
| **Device driver packages** | older copies of drivers | usually safe; Windows keeps the current one |
| **Temporary files**, **Thumbnails**, **DirectX Shader Cache** | caches | safe; rebuild automatically |
| **Recycle Bin** | deleted files | look inside first |
| **Previous Windows installation(s)** | the `Windows.old` folder | often **10–30 GB**; it exists so you can roll back an update, and Windows removes it by itself after a while. Removing it early ends the rollback option. |
| **Downloads** | your Downloads folder | ⚠️ **Do not tick this** unless you have checked the folder. These are your files. |

Tick what you want and choose **Remove files**. The classic tool, `cleanmgr` → *Clean up system files*, shows the same list.

## 4. Uninstall what you don't use (5 minutes)

Open **Settings → Apps → Installed apps** (Windows 10: *Apps & features*) and **sort by size**. Look for:

- games you finished or never started (the biggest single win on many PCs),
- creative and engineering suites you no longer open,
- duplicate runtimes and SDKs (several versions of the same SDK),
- trial software and old "helper" tools that came with the PC.

Uninstalling from here removes the app properly. **Never delete a program's folder by hand.**

## 5. Hunt big files (10 minutes)

A few forgotten files often hold more space than hundreds of small ones: ISOs, screen recordings, old backups, installers.

- In File Explorer, open **Downloads**, **Videos**, **Desktop** or **Documents** and type `size:gigantic` in the search box (files over 128 MB), then sort by size.
- Or use a disk-usage visualizer such as WinDirStat or WizTree (third-party tools, not affiliated with this project): they draw a map of what fills the drive.

Delete what you are sure about. For anything you might need, go to step 6.

## 6. Move, don't delete (10 minutes)

If you want to keep it but not on C:

- **OneDrive Files On-Demand:** right-click a OneDrive folder → **Free up space**. Files stay in the cloud and use almost no local space until opened.
- **Library folders:** right-click *Downloads*, *Documents*, *Pictures* or *Videos* → **Properties → Location → Move** to another drive.
- **Game libraries:** most launchers can add a library folder on another drive and move installed games there (look for *Storage* or *Install folder* settings).
- **New content:** *Settings → System → Storage → Advanced storage settings → Where new content is saved* sets other drives as the default for new apps and documents (wording varies by Windows version).

A hard disk is fine for archives and media; keep programs you use daily on the SSD.

## 7. Keep it clean (2 minutes, once)

- Turn on **Storage Sense** (*Settings → System → Storage → Storage Sense*) to remove temporary files and empty the Recycle Bin on a schedule. Be careful with its Downloads option.
- Run RetroBoost **about once a month**, or whenever the gauge turns red.
- If a Windows update fails with a space error, repeat steps 2–4 first.

---

## Bonus: developer extras

Developer machines fill up faster. Besides the caches RetroBoost clears:

| Where | What to do |
|---|---|
| **Docker Desktop** | `docker system df` shows usage; `docker system prune` removes stopped containers, unused networks and dangling images. The WSL 2 virtual disk does not shrink by itself afterwards; see Docker's and Microsoft's WSL documentation for compacting it. |
| **WSL distributions** | `wsl --list --verbose` shows them. Unregistering a distribution **deletes its data**: export it first. |
| **`node_modules`** | old project folders can hold hundreds of MB each; delete the ones for projects you no longer build (`npm install` brings them back). |
| **Visual Studio** | run the installer and remove unused workloads and old versions; clean its download cache. |
| **Python** | remove unused virtual environments; `conda clean --all` for Conda. |
| **Gradle and Maven** | `%USERPROFILE%\.gradle\caches` and `%USERPROFILE%\.m2\repository` can be deleted and will be downloaded again. |
| **Android emulators** | remove system images and virtual devices you don't use. |

## Bonus: advanced system features (read the trade-offs)

These are legitimate but each has a cost. Skip them unless you understand it.

| Feature | Space | Trade-off |
|---|---|---|
| **Hibernation file** (`hiberfil.sys`) | roughly 40–75% of your RAM size | `powercfg /h off` (as administrator) removes it but disables hibernate **and Fast Startup**. `powercfg /h /type reduced` keeps Fast Startup and drops full hibernation. |
| **System Restore** | a few GB | *System Properties → System Protection → Configure* lets you lower the maximum usage; less room to roll back. |
| **Page file** (`pagefile.sys`) | several GB | **Don't disable it.** If you must, move it to another SSD and keep a small one on C:. |

## What never to delete

Windows and your programs depend on these. Removing them breaks things, often in ways that don't show up until the next update.

- `C:\Windows\WinSxS`, `C:\Windows\System32`, `C:\Windows\Installer`
- `C:\Program Files\WindowsApps` (uninstall Store apps from Settings instead)
- `C:\ProgramData\Package Cache` (needed to repair and uninstall some programs)
- `pagefile.sys`, `System Volume Information`, `C:\Recovery`
- the *Driver Store* by hand (use *Device driver packages* in step 3)

And skip "registry cleaners" and "PC optimizer" suites: they promise a lot and risk more than they return.

## How RetroBoost fits in

| Plan step | RetroBoost |
|---|---|
| 1 Measure | the disk gauge on the main screen |
| 2 Safe junk | **BOOST NOW** and **DISK CLEAN** |
| 3 Windows cleanup | `W` on the Disk screen opens the right Settings page |
| 4–6 | out of scope today ([ideas on the roadmap](ROADMAP.md): a big-files explorer) |
| 7 Keep it clean | run it monthly |

Have a tip that belongs in this guide? [Send a pull request](../CONTRIBUTING.md): this is the most useful page for non-developers.
