# Third-party notices

RetroBoost's own code is MIT-licensed (see [LICENSE](LICENSE)). The three rule files in [`data/`](data/) come from other open projects and keep their own licenses. Thank you to both projects: RetroBoost 2.0 stands on their work.

| File | Used by | From | License |
|---|---|---|---|
| `data/Winapp2.ini` | APP CLEAN | [Winapp2](https://github.com/MoscaDotTo/Winapp2), as bundled with FluentCleaner | CC BY-SA 4.0 |
| `data/WinRules.ini` | TWEAKS | [FluentCleaner](https://github.com/builtbybel/FluentCleaner) | MIT |
| `data/AppRules.ini` | UNINSTALL | [FluentCleaner](https://github.com/builtbybel/FluentCleaner) | MIT |

All three are copied **unmodified** from FluentCleaner at commit `d666d61` (FluentCleaner 26.11.11, 15 November 2026).

## Winapp2.ini: Creative Commons Attribution-ShareAlike 4.0

`data/Winapp2.ini` (version `260828-custom`, 4,076 entries) is the community cleaning database of the **Winapp2 project**, <https://github.com/MoscaDotTo/Winapp2>. It is licensed under the [Creative Commons Attribution-ShareAlike 4.0 International license](https://creativecommons.org/licenses/by-sa/4.0/); the file's own header carries the notice and a link to the project's [license agreement](https://github.com/MoscaDotTo/Winapp2/blob/master/License.md).

The license covers that file only, not RetroBoost's code, which reads it as data. If you change `Winapp2.ini` and share it, share it under the same license and credit the Winapp2 project. Want more or newer rules? Drop any winapp2-format `.ini` into `%LOCALAPPDATA%\RetroBoost\custom\` (see the README).

## FluentCleaner: MIT

`data/WinRules.ini` and `data/AppRules.ini` come from **FluentCleaner**, <https://github.com/builtbybel/FluentCleaner>. The APP CLEAN engine (winapp2 parsing, detection, `ExcludeKey` handling, the deletable-file check, `REMOVESELF`), the TWEAKS engine (apply, read back, undo) and the UNINSTALL logic (rule classification, the silent-first uninstall chain) in [`src/retroboost.ps1`](src/retroboost.ps1) are PowerShell ports of FluentCleaner's C# code. FluentCleaner's license:

```text
MIT License

Copyright (c) 2026 A Belim app creation

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

RetroBoost is not affiliated with FluentCleaner, the Winapp2 project or their authors. Product names belong to their owners.
