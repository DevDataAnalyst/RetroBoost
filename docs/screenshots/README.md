# Screenshots

## The generated images

`main.png`, `disk.png`, `ram.png`, `processes.png`, `settings.png`, `help.png`, `plan.png`, `running.png`, `result.png`, `theme-green.png` and `theme-amber.png` are **rendered by [`tools/Render-Screenshots.ps1`](../../tools/Render-Screenshots.ps1)** from the app's own screen buffer, using the built-in `-Demo` data. They contain invented numbers and program names: nothing from a real PC.

Regenerate them after any UI change (Windows only):

```powershell
pwsh -File tools/Render-Screenshots.ps1
```

## Add real terminal captures (help wanted)

The README has empty slots waiting for real screenshots and GIFs. To add yours:

1. Run `RetroBoost.cmd -Demo` (so no personal data ends up in the picture) in a terminal at least 80×26.
2. Capture it: Windows Terminal → <kbd>Win</kbd>+<kbd>Shift</kbd>+<kbd>S</kbd> (Snipping Tool) for a PNG; [ScreenToGif](https://www.screentogif.com/) or similar for a GIF.
3. Save it here with one of these names (or a new descriptive one):

   | File | Shows |
   |---|---|
   | `real-windows-terminal.png` | the main screen in Windows Terminal |
   | `real-console-host.png` | the main screen in the classic console host |
   | `real-yours.png` | your terminal, font or theme |
   | `boot-splash.gif` | the animated BIOS boot splash |
   | `one-click.png` | the one-click countdown dialog |
   | `demo-tour.gif` | a short tour of the screens |

4. Replace the matching *"your screenshot here"* cell in the README table with `<img src="docs/screenshots/<file>" width="380">`, and open a pull request.

Please keep each file under about 1.5 MB (resize or trim GIFs) and **never include real usernames, paths or program lists**: use `-Demo`.
