# Security policy

RetroBoost deletes files and stops programs, so a bug can matter. These are treated as **security-relevant** and fixed first:

- RetroBoost deletes, or offers to delete, something outside the documented categories (see [docs/SAFETY.md](docs/SAFETY.md)).
- It can stop a protected program (Windows core, security tools, the terminal).
- A crafted `config.json`, folder name or file name makes it act on the wrong target (for example path traversal or an unexpected wildcard match).
- It makes a network call, or leaks personal data into logs or screenshots.

## Supported versions

The latest [release](https://github.com/DevDataAnalyst/RetroBoost/releases/latest) and the `main` branch.

## How to report

- **Most issues:** open a [GitHub issue](https://github.com/DevDataAnalyst/RetroBoost/issues/new/choose) and put *"Security:"* in the title. Include steps to reproduce, your Windows and PowerShell versions, and the log (remove personal paths).
- **Anything sensitive or easy to abuse:** open an issue titled *"Security: please contact me"* **without details**, and a maintainer will arrange a private channel through GitHub.

You will get an acknowledgement as soon as a maintainer can, and credit in the release notes if you wish.

## Good to know

- RetroBoost is an unsigned script that runs with your normal user rights. It never asks for administrator rights.
- It makes no network calls. If you see one, that is a bug.
- You can read the whole program in [`src/retroboost.ps1`](src/retroboost.ps1) and run it safely with `-Demo` or `-DryRun`.
