# Security policy

RetroBoost deletes files and stops programs, so a bug can matter. These are treated as **security-relevant** and fixed first:

- RetroBoost deletes, or offers to delete, something outside the documented categories, or an APP CLEAN rule gets past the guards (your folders, the Windows folder; see [docs/SAFETY.md](docs/SAFETY.md)).
- It can stop a protected program (Windows core, security tools, the terminal), or offer to uninstall a protected app.
- A tweak writes something other than what the catalogue says, or claims success when Windows did not keep the value.
- A crafted `config.json`, folder name or file name makes it act on the wrong target (for example path traversal or an unexpected wildcard match).
- It makes a network call, or leaks personal data into logs or screenshots.

## Supported versions

The latest [release](https://github.com/DevDataAnalyst/RetroBoost/releases/latest) and the `main` branch.

## How to report

- **Most issues:** open a [GitHub issue](https://github.com/DevDataAnalyst/RetroBoost/issues/new/choose) and put *"Security:"* in the title. Include steps to reproduce, your Windows and PowerShell versions, and the log (remove personal paths).
- **Anything sensitive or easy to abuse:** open an issue titled *"Security: please contact me"* **without details**, and a maintainer will arrange a private channel through GitHub.

You will get an acknowledgement as soon as a maintainer can, and credit in the release notes if you wish.

## Good to know

- RetroBoost is an unsigned script that runs with your normal user rights. It never asks for administrator rights (you may start it elevated to unlock the `[A]` tweaks).
- What APP CLEAN deletes is decided by rule files (`data/Winapp2.ini` and your own `custom\*.ini`), always inside the guards. A rule file is data you choose to trust, like a script: only add rules from sources you trust.
- It makes no network calls. If you see one, that is a bug.
- You can read the whole program in [`src/retroboost.ps1`](src/retroboost.ps1) and run it safely with `-Demo` or `-DryRun`.
