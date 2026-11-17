## What does this change?

<!-- A sentence or two, and the issue it closes (e.g. "Closes #12"). -->

## Why?

<!-- The problem or idea behind it. -->

## How did you test it?

- [ ] `pwsh -File tests/selftest.ps1` prints `all checks passed`
- [ ] Tried it with `-Demo` and/or `-DryRun`
- [ ] If it deletes, writes settings, uninstalls or stops anything: covered by a **sandbox test** (never tested on real folders, keys or apps)

## Checklist

- [ ] Regenerable data by default (anything riskier starts unticked); the guards are not weakened; no admin needed unless marked `[A]`; a running-app guard if files can be locked
- [ ] UI text fits the 78×25 grid (`-Screenshot all`), screenshots regenerated if the UI changed
- [ ] Docs updated (README, `docs/SAFETY.md`, `CHANGELOG.md`) where relevant
- [ ] I agree my contribution is licensed under the MIT License

<!-- Thank you! 🕹️ -->
