#Requires -Version 7
<#
.SYNOPSIS
RETROBOOST - a retro text-mode PC tune-up: free disk space, clean 4,000+ apps, switch off Windows ads, remove bloatware,
trim RAM and stop unwanted programs.

.DESCRIPTION
Start it, press ENTER on BOOST NOW, press ENTER again to confirm. BOOST cleans safe junk (temp files, package and
browser caches, installer downloads, crash dumps), trims RAM and closes the programs on YOUR kill list. The kill list
starts empty: add programs on the PROCESSES screen with K. APP CLEAN runs the community winapp2.ini cleaners, TWEAKS
switches off Windows ads, tips and telemetry (with undo) and UNINSTALL removes Store apps and programs: ideas and rule
files ported from FluentCleaner (https://github.com/builtbybel/FluentCleaner). Windows and security processes are
protected and can never be stopped from here. -DryRun shows everything and changes nothing. Every action is logged to
%LOCALAPPDATA%\RetroBoost\boost.log. Keys: arrows move, ENTER selects, SPACE ticks, ESC goes back, F1 is help.

.EXAMPLE
pwsh -File .\retroboost.ps1               # the app

.EXAMPLE
pwsh -File .\retroboost.ps1 -Boost -Yes   # one click: 3-second countdown (ESC cancels), then BOOST

.EXAMPLE
pwsh -File .\retroboost.ps1 -DryRun       # try everything, change nothing

.EXAMPLE
pwsh -File .\retroboost.ps1 -Demo         # a tour with invented data: nothing on your PC is read, changed or stopped

.EXAMPLE
pwsh -File .\retroboost.ps1 -Auto         # no screen: clean the safe junk (plus your APP CLEAN ticks if switched on), log, exit
#>
[CmdletBinding()]
param(
    [switch]$Boost, [switch]$Yes, [switch]$DryRun, [switch]$Demo, [switch]$Auto, [switch]$Shutdown,
    [ValidateSet('blue', 'green', 'amber')][string]$Theme,
    [string]$ConfigDir = (Join-Path $env:LOCALAPPDATA 'RetroBoost'),
    # test hooks: a sandbox folder replaces the real cache locations; scripted keys; plain-text screens; frame export
    [string]$Sandbox, [string[]]$Keys, [string]$Screenshot, [string]$Dump
)
if ($Keys) { $Keys = $Keys -split '[,\s]+' | Where-Object { $_ } }   # pwsh -File hands "a,b" over as one string

$script:Dry = [bool]$DryRun
$script:Test = [bool]($Keys -or $Screenshot)
$script:Quiet = $script:Test -or $Auto           # no drawing: tests and the windowless -Auto run
$script:IsAdmin = -not $Demo -and ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$script:KeyQ = $null
if ($Keys) { $script:KeyQ = [System.Collections.Generic.Queue[string]]::new([string[]]$Keys) }   # direct assignment: an if-expression would unroll the queue
$script:AutoYes = [bool]($Boost -and $Yes)       # one-click launch: a countdown replaces the plan screen
$script:ExitAfter = $script:AutoYes              # ...and the app closes after the result screen
$script:Dirty = $false
$script:Frame = 0
$script:Dumped = [System.Collections.Generic.List[object]]::new()
$script:DemoDisk = 0L; $script:DemoRam = 0L      # -Demo: the pretend gains shown after a BOOST
$ErrorActionPreference = if ($script:Test) { 'Continue' } else { 'SilentlyContinue' }   # one locked file must never crash a tune-up

$pLocal = if ($Sandbox) { "$Sandbox\Local" } else { $env:LOCALAPPDATA }
$pRoam = if ($Sandbox) { "$Sandbox\Roaming" } else { $env:APPDATA }
$pTemp = if ($Sandbox) { "$Sandbox\Temp" } else { $env:TEMP }
$pHome = if ($Sandbox) { "$Sandbox\home" } else { $env:USERPROFILE }
$dataDir = if ($Sandbox) { "$Sandbox\data" } else { [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\data')) }   # rule files: Winapp2.ini, WinRules.ini, AppRules.ini
$selfPath = $PSCommandPath   # this script, for the scheduled -Auto task

# ---------- settings and log ----------
$cfgFile = Join-Path $ConfigDir 'config.json'
$logFile = Join-Path $ConfigDir 'boost.log'
# appClean: the APP CLEAN ticks you saved (null = the safe defaults); exclude: winapp2-style PATH|dir[|pattern] / FILE|dir|name lines
$cfg = [ordered]@{ theme = 'blue'; sound = $true; confirm = $true; killList = @(); boostApps = $false; schedule = 'off'; appClean = $null; exclude = @() }
if (Test-Path -LiteralPath $cfgFile) {
    try { $j = Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json; foreach ($k in @($cfg.Keys)) { if ($null -ne $j.$k) { $cfg[$k] = $j.$k } } } catch { }
}
$cfg.killList = @($cfg.killList | ForEach-Object { "$_" } | Where-Object { $_ })
$cfg.exclude = @($cfg.exclude | ForEach-Object { "$_" } | Where-Object { $_ })
if ($null -ne $cfg.appClean) { $cfg.appClean = @($cfg.appClean | ForEach-Object { "$_" }) }
if ($Theme) { $cfg.theme = $Theme }
if ($Demo) { $cfg.killList = @('chatapp', 'gamelauncher', 'updater-agent'); $cfg.sound = $false; $logFile = '%LOCALAPPDATA%\RetroBoost\boost.log' }
function Save-Cfg { if ($script:Dirty -and -not $Demo) { try { $null = New-Item -ItemType Directory -Force -Path $ConfigDir; $cfg | ConvertTo-Json | Set-Content -LiteralPath $cfgFile } catch { } } }
function Write-Log([string]$m) { if ($Demo) { return }; try { $null = New-Item -ItemType Directory -Force -Path $ConfigDir; Add-Content -LiteralPath $logFile ('{0:yyyy-MM-dd HH:mm:ss} {1}{2}' -f (Get-Date), $(if ($script:Dry) { '[DRY] ' }), $m) } catch { } }

# ---------- helpers ----------
function Gb($b) { '{0:N2} GB' -f ($b / 1GB) }
function Mb($b) { '{0:N0} MB' -f ($b / 1MB) }
function Sz($b) { if ($b -lt 1KB) { "$b B" } elseif ($b -lt 1MB) { '{0:N0} KB' -f ($b / 1KB) } elseif ($b -lt 1GB) { '{0:N1} MB' -f ($b / 1MB) } else { Gb $b } }
function Fit([string]$s, [int]$n) { if ($s.Length -gt $n) { $s.Substring(0, $n) } else { $s.PadRight($n) } }
function Wrap([string]$s, [int]$n) {   # word wrap into lines of at most $n characters
    $line = ''
    foreach ($w in ($s -split '\s+' | Where-Object { $_ })) { if ($line -and ($line.Length + 1 + $w.Length) -gt $n) { $line; $line = $w } else { $line = ($line + ' ' + $w).Trim() } }
    if ($line) { $line }
}
function Center([string]$s) { (' ' * [Math]::Max(0, [int](($COLS - $s.Length) / 2))) + $s }
function Get-Sys {
    if ($Demo) { return [pscustomobject]@{ RamTotal = [long]16GB; RamFree = [long](5.9GB + $script:DemoRam); DiskTotal = [long]237GB; DiskFree = [long](17.3GB + $script:DemoDisk) } }
    $os = Get-CimInstance Win32_OperatingSystem
    $c = Get-PSDrive C
    [pscustomobject]@{ RamTotal = [long]$os.TotalVisibleMemorySize * 1KB; RamFree = [long]$os.FreePhysicalMemory * 1KB; DiskTotal = [long]($c.Used + $c.Free); DiskFree = [long]$c.Free }
}
function Get-Cpu { if ($Demo) { return 23 }; [int](Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average }
function Get-PathBytes([string]$Path) {
    $i = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $i) { return 0L }
    if (-not $i.PSIsContainer) { return [long]$i.Length }
    $o = [IO.EnumerationOptions]@{ RecurseSubdirectories = $true; IgnoreInaccessible = $true; AttributesToSkip = 'ReparsePoint' }
    $sum = 0L
    foreach ($f in $i.EnumerateFiles('*', $o)) { $sum += $f.Length }
    $sum
}
function Snd([string]$kind) {
    if (-not $cfg.sound -or $script:Test) { return }
    try {
        switch ($kind) {
            'ok' { [Console]::Beep(660, 70); [Console]::Beep(880, 70); [Console]::Beep(1320, 110) }
            'warn' { [Console]::Beep(330, 150) }
        }
    } catch { }
}

# ---------- what must never be stopped ----------
$protectedNames = 'system', 'idle', 'registry', 'smss', 'csrss', 'wininit', 'winlogon', 'services', 'lsass', 'lsm', 'svchost', 'dwm', 'fontdrvhost', 'explorer', 'sihost', 'taskhostw', 'ctfmon', 'runtimebroker', 'shellexperiencehost', 'startmenuexperiencehost', 'searchhost', 'searchapp', 'searchindexer', 'textinputhost', 'lockapp', 'spoolsv', 'audiodg', 'conhost', 'openconsole', 'windowsterminal', 'wt', 'cmd', 'powershell', 'pwsh', 'wmiprvse', 'dllhost', 'msmpeng', 'nissrv', 'securityhealthservice', 'securityhealthsystray', 'memcompression', 'applicationframehost', 'wudfhost', 'dashost', 'vmmem', 'vmcompute', 'wslservice', 'claude', 'avp', 'avpui'
function Test-Protected([string]$name, $procs) {
    if ($name.ToLower() -in $protectedNames) { return $true }
    $p = @($procs) | Select-Object -First 1
    if (-not $p) { return $true }
    $path = $p.Path
    if (-not $path -or $path -like "$env:windir\*" -or $p.SessionId -eq 0) { return $true }   # unreadable = system or elevated
    $false
}

# ---------- disk: what can be cleaned ----------
$browsers = [ordered]@{ brave = "$pLocal\BraveSoftware\Brave-Browser\User Data"; chrome = "$pLocal\Google\Chrome\User Data"; msedge = "$pLocal\Microsoft\Edge\User Data" }
$cats = @(
    @{ Id = 'temp'; Name = 'User temp files (older than 1 day)'; On = $true; Kind = 'age'; Skip = 'claude'; Paths = { $pTemp } }
    @{ Id = 'pkg'; Name = 'Package caches: npm pip uv Yarn bun NuGet'; On = $true; Paths = { "$pLocal\npm-cache", "$pLocal\uv\cache", "$pLocal\pip\cache", "$pLocal\Yarn\Cache", "$pHome\.bun\install\cache", "$pLocal\NuGet\v3-cache" } }
    @{ Id = 'browsers'; Name = 'Browser caches: Brave, Chrome, Edge'; On = $true
        Needs = { $open = @($browsers.Keys | Where-Object { (Test-Path -LiteralPath $browsers[$_]) -and (Get-Process $_ -ErrorAction SilentlyContinue) }); if ($open) { 'close ' + ($open -join ', ') } }
        Paths = { foreach ($b in $browsers.Values) { foreach ($n in 'Cache', 'Code Cache', 'GPUCache') { Get-ChildItem "$b\*\$n" -Directory -Force -ErrorAction SilentlyContinue } } } }
    @{ Id = 'updaters'; Name = 'App updater downloads (*-updater)'; On = $true; Paths = { Get-ChildItem $pLocal -Directory -Force -Filter '*-updater' -ErrorAction SilentlyContinue } }
    @{ Id = 'vscode'; Name = 'VS Code download cache + staging folders'; On = $true
        Needs = { if (Get-Process Code -ErrorAction SilentlyContinue) { 'close VS Code' } }
        Paths = { "$pRoam\Code\CachedExtensionVSIXs"; Get-ChildItem "$pHome\.vscode\extensions" -Directory -Force -ErrorAction SilentlyContinue | Where-Object Name -match '^\.[0-9a-f]{8}-[0-9a-f]{4}-' } }
    @{ Id = 'dumps'; Name = 'Crash dumps and error reports'; On = $true; Paths = { "$pLocal\CrashDumps", "$pLocal\Microsoft\Windows\WER" } }
    @{ Id = 'shaders'; Name = 'GPU shader caches (games rebuild them)'; On = $false; Paths = { "$pLocal\D3DSCache", "$pLocal\NVIDIA\DXCache", "$pLocal\NVIDIA\GLCache", "$pLocal\AMD\DxCache" } }
    @{ Id = 'recycle'; Name = 'Recycle Bin (cannot be undone)'; On = $false; Kind = 'recycle'; Paths = { 'C:\$Recycle.Bin' } }
)

function Set-Msg([string]$t, [string]$style = 'dim') { $app.msg = $t; $app.msgStyle = $style }

function Scan-Disk {
    if ($Demo) {   # fake, deterministic categories for the tour and the README screenshots
        $fake = @{ temp = 1.84; pkg = 3.12; browsers = 1.47; updaters = 0.62; vscode = 0.31; dumps = 0.18; shaders = 0.74; recycle = 2.05 }
        $app.cats = @(foreach ($d in $cats) {
                $open = ($d.Id -eq 'vscode')   # shows what a "close the app first" row looks like
                [pscustomobject]@{ Id = $d.Id; Name = $d.Name; On = $d.On; Kind = $d.Kind; Skip = $d.Skip; Ready = -not $open; Why = $(if ($open) { 'close VS Code' } else { '' }); Bytes = [long]($fake[$d.Id] * 1GB); Items = @(); Files = @() }
            })
        return
    }
    $list = foreach ($d in $cats) {
        Set-Msg "SCANNING  $($d.Name) ..."
        if (-not $script:Quiet) { Redraw }
        $c = [pscustomobject]@{ Id = $d.Id; Name = $d.Name; On = $d.On; Kind = $d.Kind; Skip = $d.Skip; Ready = $true; Why = ''; Bytes = 0L; Items = @(); Files = @() }
        $why = $null
        if ($Sandbox -and $d.Kind -eq 'recycle') { $why = 'sandbox' }
        else {
            if ($d.Needs) { $why = & $d.Needs }
            $c.Items = @(& $d.Paths | ForEach-Object { if ($_ -is [IO.FileSystemInfo]) { $_.FullName } else { "$_" } } | Where-Object { Test-Path -LiteralPath $_ })
            if ($d.Kind -eq 'age' -and $c.Items) {
                $root = $c.Items[0]; $cut = (Get-Date).AddDays(-1)
                $o = [IO.EnumerationOptions]@{ RecurseSubdirectories = $true; IgnoreInaccessible = $true; AttributesToSkip = 'ReparsePoint' }
                $c.Files = @([IO.DirectoryInfo]::new($root).EnumerateFiles('*', $o) | Where-Object { $_.LastWriteTime -lt $cut -and $_.FullName.Substring($root.Length).TrimStart('\').Split('\')[0] -notin $d.Skip })
                $c.Bytes = [long]($c.Files | Measure-Object Length -Sum).Sum
            } else { $c.Bytes = [long]($c.Items | ForEach-Object { Get-PathBytes $_ } | Measure-Object -Sum).Sum }
        }
        if ($why) { $c.Ready = $false; $c.Why = $why } elseif ($c.Bytes -le 0) { $c.Ready = $false; $c.Why = 'nothing' }
        $c
    }
    $app.cats = @($list)
    Set-Msg ''
    if (-not $script:Quiet) { Redraw }   # clear the "SCANNING" line before any dialog is drawn on top
}

function Invoke-Clean($c) {
    if ($c.Kind -eq 'rule') { return Clean-Rule $c }   # an APP CLEAN rule
    if ($Demo) { $script:DemoDisk += $c.Bytes; return [long]$c.Bytes }
    $freed = 0L
    if ($c.Kind -eq 'age') {
        foreach ($f in $c.Files) { try { if (-not $script:Dry) { [IO.File]::Delete($f.FullName) }; $freed += $f.Length } catch { } }
    } elseif ($c.Kind -eq 'recycle') {
        if (-not $script:Dry) { Clear-RecycleBin -DriveLetter C -Force -ErrorAction SilentlyContinue }
        $freed = $c.Bytes
    } else {
        foreach ($p in $c.Items) {
            $b = Get-PathBytes $p
            if ($script:Dry) { $freed += $b; continue }
            Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
            $freed += $b - (Get-PathBytes $p)
        }
    }
    $freed
}

# ---------- processes and RAM ----------
function Load-Procs {
    if ($Demo) {   # invented program names: nothing real is read
        $fake = @(   # name, processes, MB, has a window, protected
            @('browser', 24, 2410, 1, 0), @('codeeditor', 12, 1540, 1, 0), @('mediaplayer', 9, 780, 1, 0), @('chatapp', 7, 640, 1, 0),
            @('nodeapp', 4, 420, 0, 0), @('gamelauncher', 6, 380, 0, 0), @('cloudsync', 2, 210, 0, 0), @('updater-agent', 1, 45, 0, 0),
            @('svchost', 78, 1720, 0, 1), @('MsMpEng', 1, 310, 0, 1), @('explorer', 1, 260, 1, 1), @('dwm', 1, 190, 0, 1),
            @('pwsh', 2, 150, 0, 1), @('WindowsTerminal', 1, 120, 1, 1)
        )
        $app.procs = @(foreach ($f in $fake) { [pscustomobject]@{ Name = $f[0]; N = $f[1]; Bytes = [long]$f[2] * 1MB; Win = [bool]$f[3]; Prot = [bool]$f[4] } })
        Sort-Procs; return
    }
    $rows = foreach ($g in (Get-Process | Group-Object Name)) {
        $ps = $g.Group
        [pscustomobject]@{
            Name = $g.Name; N = $g.Count; Bytes = [long]($ps | Measure-Object WorkingSet64 -Sum).Sum
            Win = [bool]($ps | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1)
            Prot = (Test-Protected $g.Name $ps)
        }
    }
    $app.procs = @($rows)
    Sort-Procs
}
function Sort-Procs { $app.plist = @(if ($app.psort -eq 'mem') { $app.procs | Sort-Object Bytes -Descending } else { $app.procs | Sort-Object Name }) }

function Get-KillTargets {
    if ($Demo) { if (-not $app.procs.Count) { Load-Procs }; return @($cfg.killList | Where-Object { $n = $_; $app.procs | Where-Object { $_.Name -ieq $n -and -not $_.Prot } }) }
    $running = Get-Process | Group-Object Name
    foreach ($n in $cfg.killList) {
        $g = $running | Where-Object { $_.Name -ieq $n } | Select-Object -First 1
        if ($g -and -not (Test-Protected $g.Name $g.Group)) { $g.Name }
    }
}

# windowed programs are asked to close (they may offer to save); background ones are ended
function Stop-App([string]$name, [bool]$force) {
    if ($Demo) {
        $p = $app.procs | Where-Object { $_.Name -ieq $name -and -not $_.Prot } | Select-Object -First 1
        if (-not $p) { return [pscustomobject]@{ Closed = 0; Left = 0 } }
        $script:DemoRam += $p.Bytes; return [pscustomobject]@{ Closed = $p.N; Left = 0 }
    }
    $ps = @(Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID })
    if (-not $ps -or (Test-Protected $name $ps)) { return [pscustomobject]@{ Closed = 0; Left = 0 } }
    if ($script:Dry) { return [pscustomobject]@{ Closed = $ps.Count; Left = 0 } }
    $win = @($ps | Where-Object { $_.MainWindowHandle -ne 0 })
    foreach ($p in $win) { try { if ($force) { $p.Kill() } else { [void]$p.CloseMainWindow() } } catch { } }
    foreach ($p in $win) { try { [void]$p.WaitForExit(4000) } catch { } }
    $rem = @(Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID })
    if ($rem | Where-Object { $_.MainWindowHandle -ne 0 }) { return [pscustomobject]@{ Closed = $ps.Count - $rem.Count; Left = $rem.Count } }   # a window is still open: leave the rest alone
    foreach ($p in $rem) { try { $p.Kill(); [void]$p.WaitForExit(2000) } catch { } }
    $left = @(Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID }).Count
    [pscustomobject]@{ Closed = $ps.Count - $left; Left = $left }
}

function Use-Native {   # a few Windows calls, compiled once on first use
    if (-not ('RB.Win32' -as [type])) {
        Add-Type -Namespace RB -Name Win32 -MemberDefinition @'
[DllImport("psapi.dll")] public static extern bool EmptyWorkingSet(IntPtr hProcess);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, string lParam, uint flags, uint timeout, out IntPtr result);
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr sa, uint disposition, uint flags, IntPtr template);
// asks for DELETE access the way a delete would: false for files in use without share-delete, or that need admin
public static bool CanDelete(string path) { using (var h = CreateFileW(path, 0x00010000, 7, IntPtr.Zero, 3, 0x00200000, IntPtr.Zero)) { return !h.IsInvalid; } }
'@
    }
}

# ponytail: working-set trim only; flushing the standby list needs admin and is left out
function Invoke-RamTrim {
    $before = (Get-Sys).RamFree; $n = 0
    if ($Demo) { $script:DemoRam += 640MB; return [pscustomobject]@{ Before = $before; After = (Get-Sys).RamFree; Count = 88 } }
    if (-not $script:Dry) {
        Use-Native
        $filter = if ($Sandbox) { 'rbtest*' } else { '*' }
        foreach ($p in Get-Process -Name $filter -ErrorAction SilentlyContinue) { try { if ([RB.Win32]::EmptyWorkingSet($p.Handle)) { $n++ } } catch { } }
        Start-Sleep -Milliseconds 500
    }
    [pscustomobject]@{ Before = $before; After = (Get-Sys).RamFree; Count = $n }
}

# ---------- registry helpers (app cleaners and tweaks) ----------
$hives = @{ HKCU = 'CurrentUser'; HKEY_CURRENT_USER = 'CurrentUser'; HKLM = 'LocalMachine'; HKEY_LOCAL_MACHINE = 'LocalMachine'; HKCR = 'ClassesRoot'; HKEY_CLASSES_ROOT = 'ClassesRoot'; HKU = 'Users'; HKEY_USERS = 'Users'; HKCC = 'CurrentConfig'; HKEY_CURRENT_CONFIG = 'CurrentConfig' }
function Split-Reg([string]$path) {   # 'HKCU\Software\X' -> registry root + subkey
    $i = $path.IndexOf('\'); $h = $hives[$(if ($i -ge 0) { $path.Substring(0, $i) } else { $path })]
    [pscustomobject]@{ Root = $(if ($h) { [Microsoft.Win32.Registry]::$h }); Sub = $(if ($i -ge 0) { $path.Substring($i + 1).Trim('\') } else { '' }) }
}
function Format-RegPath([string]$p) {   # one spelling for comparisons: HKEY_CURRENT_USER\X\ -> HKCU\X
    $q = $p.Trim().TrimEnd('\'); $i = $q.IndexOf('\'); $h = if ($i -ge 0) { $q.Substring(0, $i) } else { $q }
    $s = @{ HKEY_CURRENT_USER = 'HKCU'; HKEY_LOCAL_MACHINE = 'HKLM'; HKEY_USERS = 'HKU'; HKEY_CURRENT_CONFIG = 'HKCC'; HKEY_CLASSES_ROOT = 'HKCR' }[$h]
    if ($s) { $s + $q.Substring($h.Length) } else { $q }
}
function Test-Reg([string]$path) {   # key exists (and, after a |, that value too)
    $v = $null; $j = $path.LastIndexOf('|'); if ($j -ge 0) { $v = $path.Substring($j + 1); $path = $path.Substring(0, $j) }
    $q = Split-Reg $path; if (-not $q.Root) { return $false }
    try { $k = $q.Root.OpenSubKey($q.Sub); if (-not $k) { return $false }; try { -not $v -or $null -ne $k.GetValue($v) } finally { $k.Dispose() } } catch { $false }
}

# ---------- APP CLEAN: the winapp2.ini engine (ported from FluentCleaner) ----------
# winapp2 %Variables%; under -Sandbox every location is redirected into the sandbox
$sbx = { param($real, $name) if ($Sandbox) { "$Sandbox\$name" } else { $real } }
$known = [ordered]@{
    '%LocalAppData%' = $pLocal; '%AppData%' = $pRoam; '%Temp%' = $pTemp; '%Tmp%' = $pTemp; '%UserProfile%' = $pHome
    '%LocalLowAppData%' = & $sbx ([IO.Path]::GetFullPath("$env:LOCALAPPDATA\..\LocalLow")) 'LocalLow'
    '%Documents%' = & $sbx ([Environment]::GetFolderPath('MyDocuments')) 'home\Documents'; '%Desktop%' = & $sbx ([Environment]::GetFolderPath('DesktopDirectory')) 'home\Desktop'
    '%Music%' = & $sbx ([Environment]::GetFolderPath('MyMusic')) 'home\Music'; '%Pictures%' = & $sbx ([Environment]::GetFolderPath('MyPictures')) 'home\Pictures'
    '%Videos%' = & $sbx ([Environment]::GetFolderPath('MyVideos')) 'home\Videos'
    '%ProgramFiles%' = & $sbx $env:ProgramFiles 'ProgramFiles'; '%ProgramFiles(x86)%' = & $sbx ${env:ProgramFiles(x86)} 'ProgramFilesX86'; '%ProgramFilesX86%' = & $sbx ${env:ProgramFiles(x86)} 'ProgramFilesX86'
    '%ProgramData%' = & $sbx $env:ProgramData 'ProgramData'; '%CommonAppData%' = & $sbx $env:ProgramData 'ProgramData'
    '%SystemRoot%' = & $sbx $env:SystemRoot 'Windows'; '%WinDir%' = & $sbx $env:windir 'Windows'; '%System%' = & $sbx ([Environment]::GetFolderPath('System')) 'Windows\System32'
    '%SystemX86%' = & $sbx ([Environment]::GetFolderPath('SystemX86')) 'Windows\SysWOW64'; '%SystemDrive%' = & $sbx $env:SystemDrive 'SystemDrive'
}
$dlDir = if ($Sandbox) { "$Sandbox\home\Downloads" } else { try { [Environment]::ExpandEnvironmentVariables((Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' '{374DE290-123F-4565-9164-39C4925E467B}' -ErrorAction Stop)) } catch { "$env:USERPROFILE\Downloads" } }
# whatever a rule says, these are never touched: your files, the whole Windows folder (Windows cleans itself: W on
# DISK CLEAN), Store app installs, installer caches, and the AI assistant's temp folder
$never = @(foreach ($d in $known['%Documents%'], $known['%Desktop%'], $known['%Music%'], $known['%Pictures%'], $known['%Videos%'], $dlDir, $env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial,
        $env:windir, $known['%WinDir%'], "$($known['%ProgramFiles%'])\WindowsApps", "$($known['%ProgramData%'])\Package Cache", "$pTemp\claude") { if ($d) { $d.TrimEnd('\') + '\' } })
$dayAgo = (Get-Date).AddDays(-1)
$script:UserExcl = @(); $script:UserRegExcl = @()   # your config.json "exclude" lines, read with the rules
$refs = @{ 3006 = 'Microsoft Edge'; 3021 = 'Applications'; 3022 = 'Internet'; 3023 = 'Multimedia'; 3024 = 'Utilities'; 3025 = 'Windows'; 3026 = 'Firefox'; 3027 = 'Opera'; 3028 = 'Safari'; 3029 = 'Google Chrome'; 3030 = 'Thunderbird'; 3031 = 'Microsoft Store'; 3033 = 'Vivaldi'; 3034 = 'Brave'; 3035 = 'Opera GX'; 3036 = 'Spotify'; 3037 = 'Avast Secure Browser'; 3038 = 'AVG Secure Browser'; 3039 = 'Arc Browser'; 3040 = 'iTunes'; 3042 = 'WhatsApp'; 3043 = 'Norton Private Browser'; 3044 = 'Avira Secure Browser' }
$ruleApps = @{ 3006 = 'msedge', 'Edge'; 3026 = 'firefox', 'Firefox'; 3027 = 'opera', 'Opera'; 3029 = 'chrome', 'Chrome'; 3030 = 'thunderbird', 'Thunderbird'; 3033 = 'vivaldi', 'Vivaldi'; 3034 = 'brave', 'Brave'; 3035 = 'opera', 'Opera' }   # browser rules wait until it is closed
$special = @{ DET_CHROME = '%LocalAppData%\Google\Chrome\User Data'; DET_FIREFOX = '%AppData%\Mozilla\Firefox'; DET_THUNDERBIRD = '%AppData%\Thunderbird'; DET_OPERA = '%AppData%\Opera Software\Opera Stable'; DET_EDGE = '%LocalAppData%\Microsoft\Edge\User Data'; DET_WINSTORE = '%LocalAppData%\Packages'; DET_IE = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\IEXPLORE.EXE' }
# ponytail: name keywords pick the pre-ticked rules; a curated list would be stricter if this ticks something odd
$safeTick = '\b(cache|caches|temp|temporary|logs?|crash\w*|dumps?|thumbnails?|telemetry|error reporting)\b'
function Get-SafeTick($r) { $r.Def -and -not $r.Warn -and $r.Name -match $safeTick -and $r.Name -notmatch 'shader' }

function Expand-W([string]$p) {
    $p = [Environment]::ExpandEnvironmentVariables(($p -replace '%[^%\\]+%', { $v = $known[$_.Value]; if ($v) { $v } else { $_.Value } }))
    if ($p.Length -eq 2 -and $p[1] -eq ':') { $p += '\' }   # a bare "C:" means the current folder of C:, not its root
    $p
}
function Resolve-W([string]$raw) {   # every path a winapp2 path names: %Variables% expanded, * and ? segments walked
    $out = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    Find-W (Expand-W $raw) $out
    if ($raw -match '%ProgramFiles%') { Find-W (Expand-W ($raw -ireplace '%ProgramFiles%', '%ProgramFiles(x86)%')) $out }   # winapp2 writes %ProgramFiles% for both
    , $out
}
function Find-W([string]$p, $out) {
    $parts = $p.Split('\'); $i = 0
    while ($i -lt $parts.Count -and $parts[$i].IndexOfAny([char[]]'*?') -lt 0) { $i++ }
    if ($i -eq $parts.Count) { [void]$out.Add($p); return }
    if ($i -eq 0) { return }
    $base = $parts[0..($i - 1)] -join '\'; if ($base.Length -eq 2) { $base += '\' }
    if (-not [IO.Directory]::Exists($base)) { return }
    $rest = if ($i + 1 -lt $parts.Count) { $parts[($i + 1)..($parts.Count - 1)] -join '\' } else { $null }
    try {
        foreach ($m in $(if ($null -ne $rest) { [IO.Directory]::GetDirectories($base, $parts[$i]) } else { [IO.Directory]::GetFileSystemEntries($base, $parts[$i]) })) {
            if ($null -ne $rest) { Find-W "$m\$rest" $out } else { [void]$out.Add($m) }
        }
    } catch { }
}
function Test-Exists([string]$raw) { foreach ($p in (Resolve-W $raw)) { if ([IO.File]::Exists($p) -or [IO.Directory]::Exists($p)) { return $true } }; $false }
function Test-Never([string]$p) { foreach ($d in $never) { if ($p.StartsWith($d, 'OrdinalIgnoreCase') -or "$p\" -ieq $d) { return $true } }; $false }

# winapp2 ExcludeKey lines: FILE|dir\|name (that file only), PATH|dir\[|pattern] (the whole tree, or matching files in it)
function Get-Excl($lines) {
    foreach ($l in $lines) {
        $p = $l.Split('|'); if ($p.Count -lt 2 -or $p[0].Trim() -eq 'REG') { continue }
        $pat = if ($p.Count -gt 2 -and $p[2].Trim()) { $p[2].Trim() } else { $null }
        foreach ($d in (Resolve-W $p[1].Trim())) { [pscustomobject]@{ Dir = $d.TrimEnd('\') + '\'; Pat = $pat; Wild = [bool]($pat -and $pat.IndexOfAny([char[]]'*?') -ge 0) } }
    }
}
function Get-RegExcl($lines) { foreach ($l in $lines) { $p = $l.Split('|'); if ($p.Count -gt 1 -and $p[0].Trim() -eq 'REG') { Format-RegPath $p[1] } } }
function Test-Keep([IO.FileInfo]$f, $rx) {   # $true = this file stays, whatever the rule says
    $p = $f.FullName
    if (Test-Never $p) { return $true }
    if ($p.StartsWith("$pTemp\", 'OrdinalIgnoreCase') -and $f.LastWriteTime -gt $dayAgo) { return $true }   # same rule as DISK CLEAN: fresh temp files may be in use
    if ($p.IndexOf('\IndexedDB\chrome-extension_', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }          # browser-extension databases (password managers and such)
    foreach ($x in $rx) {
        if (-not $p.StartsWith($x.Dir, 'OrdinalIgnoreCase')) { continue }
        if (-not $x.Pat) { return $true }
        if ($x.Wild) { if ([IO.Enumeration.FileSystemName]::MatchesSimpleExpression($x.Pat, $f.Name, $true)) { return $true } }
        elseif ($p.Substring($x.Dir.Length) -ieq $x.Pat) { return $true }
    }
    $false
}

function Read-Rules {   # Winapp2.ini, then your own custom\*.ini; a later rule with the same name replaces the earlier one
    $byName = [ordered]@{}
    $files = @(@(Join-Path $dataDir 'Winapp2.ini') + @(Get-ChildItem -LiteralPath (Join-Path $ConfigDir 'custom') -Filter *.ini -File -ErrorAction SilentlyContinue | ForEach-Object FullName) | Where-Object { Test-Path -LiteralPath $_ })
    foreach ($file in $files) {
        $own = -not $file.StartsWith($dataDir, 'OrdinalIgnoreCase')   # your own rules may leave out the Detect line
        $r = $null
        $done = { if ($r -and ($r.Files.Count -or $r.Regs.Count) -and ($own -or $r.Det.Count -or $r.DetF.Count -or $r.Spec)) { $byName[$r.Name] = $r } }
        foreach ($raw in [IO.File]::ReadLines($file)) {
            $line = $raw.Trim()
            if (-not $line -or $line[0] -eq ';' -or $line[0] -eq '#') { continue }
            if ($line[0] -eq '[' -and $line[-1] -eq ']') {
                & $done
                $n = $line.Substring(1, $line.Length - 2).Trim().TrimEnd('*').TrimEnd()
                $r = if ($n -like 'Winapp2*' -or $n -like 'version*') { $null } else {
                    [pscustomobject]@{ Kind = 'rule'; Id = $n; Name = $n; Ref = 0; Sec = ''; Cat = 'Other applications'; Order = 9000; Own = $own; Spec = ''; Warn = ''; Def = $true
                        Det = [Collections.Generic.List[string]]::new(); DetF = [Collections.Generic.List[string]]::new(); Files = [Collections.Generic.List[string]]::new()
                        Regs = [Collections.Generic.List[string]]::new(); Excl = [Collections.Generic.List[string]]::new()
                        On = $false; Ready = $true; Why = ''; Scanned = $false; Bytes = 0L; FileList = $null; RegList = $null }
                }
                continue
            }
            if (-not $r) { continue }
            $eq = $line.IndexOf('='); if ($eq -lt 1) { continue }
            $v = $line.Substring($eq + 1).Trim(); if (-not $v) { continue }
            $k = $line.Substring(0, $eq).Trim(); $kb = $k.TrimEnd('0123456789'); $num = $k.Length -gt $kb.Length
            switch ($kb) {
                'LangSecRef' { $r.Ref = [int]($v -as [int]) }
                'Section' { $r.Sec = $v }
                'SpecialDetect' { $r.Spec = $v }
                'Warning' { $r.Warn = $v }
                'Default' { $r.Def = $v -ne 'False' }
                'Detect' { $r.Det.Add($v) }
                'DetectFile' { $r.DetF.Add($v) }
                'FileKey' { if ($num) { $r.Files.Add($v) } }
                'RegKey' { if ($num) { $r.Regs.Add($v) } }
                'ExcludeKey' { if ($num) { $r.Excl.Add($v) } }
            }
        }
        & $done
    }
    foreach ($r in $byName.Values) { if ($refs.ContainsKey($r.Ref)) { $r.Cat = $refs[$r.Ref]; $r.Order = $r.Ref } elseif ($r.Sec) { $r.Cat = $r.Sec; $r.Order = 5000 } }
    $byName.Values
}
function Test-Rule($r) {   # is the app this rule cleans on this PC? (one hit is enough)
    if ($r.Spec -and $special[$r.Spec]) { $s = $special[$r.Spec]; return $(if ($s.StartsWith('HK')) { Test-Reg $s } else { Test-Exists $s }) }
    foreach ($d in $r.Det) { if (Test-Reg $d) { return $true } }
    foreach ($d in $r.DetF) { if (Test-Exists $d) { return $true } }
    $r.Own -and -not ($r.Det.Count + $r.DetF.Count) -and -not $r.Spec
}
function Scan-Rule($r) {   # read-only: what this rule would delete right now
    $r.FileList = [Collections.Generic.List[IO.FileInfo]]::new(); $r.RegList = [Collections.Generic.List[object]]::new(); $r.Bytes = 0L; $r.Scanned = $true
    if ($Demo) { $r.Bytes = [long]$r.DemoBytes; return }
    Use-Native
    $rx = @(Get-Excl $r.Excl) + $script:UserExcl
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($fk in $r.Files) {
        $q = $fk.Split('|'); $pat = '*.*'; $flag = ''
        if ($q.Count -eq 2) { if ($q[1].Trim() -in 'RECURSE', 'REMOVESELF') { $flag = $q[1].Trim() } else { $pat = $q[1] } } elseif ($q.Count -gt 2) { $pat = $q[1]; $flag = $q[2].Trim() }
        $pats = @($pat.Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        foreach ($d in (Resolve-W $q[0].Trim())) { Find-Files $d $pats ($flag -in 'RECURSE', 'REMOVESELF') $rx $seen $r }
    }
    $rex = @(Get-RegExcl $r.Excl) + $script:UserRegExcl
    foreach ($rk in $r.Regs) {
        $i = $rk.IndexOf('|'); $key = Format-RegPath $(if ($i -ge 0) { $rk.Substring(0, $i) } else { $rk }); $val = if ($i -ge 0) { $rk.Substring($i + 1).Trim() } else { $null }
        if ($key.Split('\').Count -lt 3) { continue }   # never a hive or a top-level key
        if (-not $script:IsAdmin -and $key -notmatch '^HKCU\\') { continue }   # machine-wide keys need admin: not counted when they cannot go
        # ponytail: an excluded branch protects its whole parent key; delete around it if a rule ever needs that
        if (@($rex | Where-Object { $key -ieq $_ -or $key.StartsWith("$_\", 'OrdinalIgnoreCase') -or $_.StartsWith("$key\", 'OrdinalIgnoreCase') }).Count) { continue }
        if (Test-Reg $(if ($val) { "$key|$val" } else { $key })) { $r.RegList.Add([pscustomobject]@{ Key = $key; Value = $val }) }
    }
}
function Find-Files([string]$dir, $pats, [bool]$deep, $rx, $seen, $r) {   # junctions and symlinks are never followed; locked files are not counted
    $di = [IO.DirectoryInfo]::new($dir); if (-not $di.Exists) { return }
    foreach ($p in $pats) { try { foreach ($f in $di.EnumerateFiles($p)) { if ($seen.Add($f.FullName) -and -not (Test-Keep $f $rx) -and [RB.Win32]::CanDelete($f.FullName)) { $r.FileList.Add($f); $r.Bytes += $f.Length } } } catch { } }
    if ($deep) { try { foreach ($d in $di.EnumerateDirectories()) { if (-not ($d.Attributes -band [IO.FileAttributes]::ReparsePoint)) { Find-Files $d.FullName $pats $true $rx $seen $r } } } catch { } }
}
function Clean-Rule($r) {   # deletes what Scan-Rule found; returns the bytes freed
    if (-not $r.Scanned) { Scan-Rule $r }
    $r.Scanned = $false   # sizes are stale once cleaned
    if ($Demo) { $script:DemoDisk += $r.Bytes; return [long]$r.Bytes }
    $freed = 0L
    foreach ($f in $r.FileList) { $n = $f.Length; try { if (-not $script:Dry) { $f.Delete() }; $freed += $n } catch { } }   # in use or read-only: skipped
    if ($script:Dry) { return $freed }
    foreach ($x in $r.RegList) { $q = Split-Reg $x.Key; try { if ($x.Value) { $k = $q.Root.OpenSubKey($q.Sub, $true); if ($k) { $k.DeleteValue($x.Value, $false); $k.Dispose() } } else { $q.Root.DeleteSubKeyTree($q.Sub, $false) } } catch { } }
    foreach ($fk in $r.Files) { $q = $fk.Split('|'); if ($q[-1].Trim() -eq 'REMOVESELF') { foreach ($d in (Resolve-W $q[0].Trim())) { Remove-Empty $d } } }
    $freed
}
function Remove-Empty([string]$dir) {   # REMOVESELF: drop the folders a clean left empty, deepest first; drive roots and known folders stay
    $di = [IO.DirectoryInfo]::new($dir)   # never TrimEnd here: "C:" alone means the current folder of C:
    if (-not $di.Exists -or -not $di.Parent -or $di.FullName.TrimEnd('\') -in @($known.Values) -or (Test-Never $di.FullName)) { return }
    $o = [IO.EnumerationOptions]@{ RecurseSubdirectories = $true; IgnoreInaccessible = $true; AttributesToSkip = 'ReparsePoint' }
    foreach ($d in @(@($di.EnumerateDirectories('*', $o)) | Sort-Object { $_.FullName.Length } -Descending) + $di) {
        try { if (-not [IO.Directory]::EnumerateFileSystemEntries($d.FullName).GetEnumerator().MoveNext()) { $d.Delete() } } catch { }
    }
}
function Group-Keep($list, [string]$by) {   # like Group-Object, but the groups keep the order of the (sorted) input
    $d = [ordered]@{}
    foreach ($x in $list) { $k = "$($x.$by)"; if (-not $d.Contains($k)) { $d[$k] = [Collections.Generic.List[object]]::new() }; $d[$k].Add($x) }
    foreach ($k in $d.Keys) { , @($k, $d[$k].ToArray()) }
}
function Load-Rules {   # parse and detect once per session; the "close the browser" checks refresh every time
    if ($null -eq $app.rules) {
        if ($Demo) {   # invented sizes on real-looking rule names: nothing on the PC is read
            $fake = @(   # name, LangSecRef, MB, pre-ticked, why it cannot run now, warning, what it cleans (several arrays per line: no leading comma)
                @('Microsoft Edge Caches', 3006, 412, 1, '', '', '%LocalAppData%\Microsoft\Edge*\User Data\*\Cache|*.*|RECURSE'), @('Microsoft Edge Web Browsing History', 3006, 18, 0, '', '', '%LocalAppData%\Microsoft\Edge*\User Data\*|History*')
                , @('Microsoft Edge Web Browsing Cookies', 3006, 6, 0, '', '', '%LocalAppData%\Microsoft\Edge*\User Data\*\Network|Cookies*')
                @('Google Chrome Caches', 3029, 655, 1, 'close Chrome', '', '%LocalAppData%\Google\Chrome*\User Data\*\Cache|*.*|RECURSE'), @('Google Chrome Bookmark Favicons', 3029, 9, 0, 'close Chrome', '', '%LocalAppData%\Google\Chrome*\User Data\*|favicons*')
                @('.Thumbnails', 3021, 145, 1, '', '', '%UserProfile%\.thumbnails|*.*|RECURSE'), @('chatapp Cache', 3021, 310, 1, '', '', '%AppData%\chatapp\Cache|*.*|RECURSE'), @('codeeditor Logs', 3021, 120, 1, '', '', '%AppData%\codeeditor\logs|*.log|RECURSE')
                @('mediaplayer Thumbnails', 3023, 45, 1, '', '', '%LocalAppData%\mediaplayer\thumbs|*.*'), @('archiver History', 3024, 1, 0, '', '', 'HKCU\Software\archiver\History'), @('gamelauncher Shader Cache', 3024, 520, 0, '', '', '%LocalAppData%\gamelauncher\shadercache|*.*|RECURSE')
                @('Windows Temporary Files', 3025, 234, 1, '', '', '%Temp%|*.*|RECURSE'), @('Windows Error Reporting', 3025, 88, 1, '', '', '%LocalAppData%\Microsoft\Windows\WER|*.*|RECURSE')
                , @('Windows Recent Documents', 3025, 1, 0, '', 'Clears the recent documents list for all user accounts on this machine.', '%AppData%\Microsoft\Windows\Recent|*.lnk')
            )
            $app.rules = @(@(foreach ($f in $fake) {
                        [pscustomobject]@{ Kind = 'rule'; Id = $f[0]; Name = $f[0]; Ref = $f[1]; Cat = $refs[$f[1]]; Order = $f[1]; Warn = $f[5]; Def = [bool]$f[3]; On = [bool]$f[3]; Ready = -not $f[4]; Why = $f[4]
                            Files = @($f[6]); Regs = @(); Scanned = $true; Bytes = [long]$f[2] * 1MB; DemoBytes = [long]$f[2] * 1MB; FileList = @(); RegList = @()
                        }
                    }) | Sort-Object Order, Name)
            return
        }
        Set-Msg 'LOADING  4,000+ app cleaners from winapp2.ini ...'; if (-not $script:Quiet) { Redraw }
        $script:UserExcl = @(Get-Excl $cfg.exclude); $script:UserRegExcl = @(Get-RegExcl $cfg.exclude)
        $app.rules = @(Read-Rules | Where-Object { Test-Rule $_ } | Sort-Object Order, Cat, Name)
        foreach ($r in $app.rules) { $r.On = if ($null -ne $cfg.appClean) { $r.Name -in $cfg.appClean } else { Get-SafeTick $r } }
        Set-Msg ''
    }
    if ($Demo -or $Sandbox) { return }
    $run = @(Get-Process | ForEach-Object Name)
    foreach ($r in $app.rules) { $a = $ruleApps[$r.Ref]; $r.Ready = -not ($a -and $run -contains $a[0]); $r.Why = if ($r.Ready) { '' } else { "close $($a[1])" } }
}
function Scan-Rules($list) {
    $i = 0
    foreach ($r in $list) { $i++; if (-not $script:Quiet) { Set-Msg ('SCANNING {0}/{1}  {2} ...' -f $i, @($list).Count, $r.Name); Redraw }; Scan-Rule $r }
    Set-Msg ''
}
function Get-RuleJobs {   # the ticked, ready rules that found something (scanned first where needed)
    $todo = @($app.rules | Where-Object { $_.On -and $_.Ready })
    Scan-Rules @($todo | Where-Object { -not $_.Scanned })
    $todo | Where-Object { $_.Bytes -gt 0 -or @($_.RegList).Count }
}
function Save-Ticks {   # remember the APP CLEAN ticks (rules not found on this PC keep their saved state)
    if (-not $app.acDirty) { return }
    $names = @($app.rules | ForEach-Object Name)
    $cfg.appClean = @(@($cfg.appClean | Where-Object { $_ -and $_ -notin $names }) + @($app.rules | Where-Object On | ForEach-Object Name))
    $app.acDirty = $false; $script:Dirty = $true
}

# ---------- TWEAKS: the WinRules.ini catalogue (ported from FluentCleaner) ----------
$win11 = [Environment]::OSVersion.Version.Build -ge 22000
function Read-Tweaks([string]$file) {   # one [section] per setting; see the header of data\WinRules.ini for the keys
    $sec = $null; $name = ''
    $close = { if ($name -and $sec) { New-Tweak $name $sec } }
    foreach ($raw in [IO.File]::ReadLines($file)) {
        $line = $raw.Trim(); if (-not $line -or $line[0] -eq ';') { continue }
        if ($line[0] -eq '[') { & $close; $name = $line.Trim('[', ']').Trim(); $sec = @{}; continue }
        $i = $line.IndexOf('=')
        if ($i -gt 0 -and $sec) { $v = $line.Substring($i + 1).Trim(); $c = $v.IndexOf(' ;'); if ($c -ge 0) { $v = $v.Substring(0, $c).Trim() }; $sec[$line.Substring(0, $i).Trim()] = $v }
    }
    & $close
}
function New-Tweak([string]$name, $sec) {   # Path/ValueName/ValueType/RecommendedValue/DefaultValue, then the same with 2, 3 ...
    $vals = [Collections.Generic.List[object]]::new()
    for ($n = 1; ; $n++) {
        $s = if ($n -gt 1) { "$n" } else { '' }
        $p = $sec["Path$s"]; if (-not $p -and $vals.Count) { $p = $vals[0].Path }
        $t = $sec["ValueType$s"]; if (-not $t) { $t = if ($vals.Count) { $vals[0].Type } else { 'DWORD' } }
        if (-not $sec["ValueName$s"] -or -not $p) { break }
        $vals.Add([pscustomobject]@{ Path = $p; Name = $sec["ValueName$s"]; Type = $t; Rec = "$($sec["RecommendedValue$s"])"; Def = "$($sec["DefaultValue$s"])" })
    }
    if (-not $vals.Count) { return }
    $adm = [bool]@($vals | Where-Object { $_.Path -match '^(HKLM|HKEY_LOCAL_MACHINE|HKCR|HKEY_CLASSES_ROOT)\\' -or $_.Path -match '\\Policies\\' }).Count   # every account on the PC: Windows wants admin
    [pscustomobject]@{ Kind = 'tweak'; Name = $name; Cat = "$($sec.Category)"; Desc = "$($sec.Description)"; Restart = "$($sec.Restart)"; Os = "$($sec.OsVersion)"; Req = "$($sec.RequiresKey)"
        Group = "$($sec.Group)"; Rec = $sec.DefaultSelected -eq 'true'; Vals = $vals.ToArray(); Admin = $adm; State = $null; Mark = $null; Locked = $false }
}
function Test-Fits($t) { (-not $t.Os -or (($t.Os -eq '11') -eq $win11)) -and (-not $t.Req -or @($t.Req.Split('|') | Where-Object { Test-Reg $_ }).Count) }
function ConvertTo-Num([string]$s) { $s = $s.Trim(); $n = [uint64]0; if ($s -match '^0x([0-9a-f]+)$') { if ([uint64]::TryParse($Matches[1], 'HexNumber', $null, [ref]$n)) { return $n } } elseif ([uint64]::TryParse($s, [ref]$n)) { return $n }; $null }
function Get-RegText($v) {   # a registry value as the catalogue spells it: numbers unsigned, binary as hex
    if ($null -eq $v) { return $null }
    if ($v -is [int]) { return [string][BitConverter]::ToUInt32([BitConverter]::GetBytes($v), 0) }
    if ($v -is [long]) { return [string][BitConverter]::ToUInt64([BitConverter]::GetBytes($v), 0) }
    if ($v -is [byte[]]) { return [Convert]::ToHexString($v) }
    if ($v -is [string[]]) { return $v -join "`n" }
    "$v"
}
function Test-TweakVal($e, [string]$want) {   # does this value stand as wanted? <delete>: the key is gone, <deletevalue>: the value is
    $q = Split-Reg $e.Path; if (-not $q.Root -or -not $q.Sub) { return $false }
    try {
        $k = $q.Root.OpenSubKey($q.Sub)
        if ($want -eq '<delete>') { if ($k) { $k.Dispose(); return $false }; return $true }
        $cur = if ($k) { Get-RegText $k.GetValue($(if ($e.Name -eq '(Default)') { '' } else { $e.Name }), $null, 'DoNotExpandEnvironmentNames'); $k.Dispose() }
        if ($want -eq '<deletevalue>') { return $null -eq $cur }
        if ($null -eq $cur) { return $false }
        if ($e.Type -in 'DWORD', 'QWORD') { $a = ConvertTo-Num $cur; $b = ConvertTo-Num $want; if ($null -ne $a -and $null -ne $b) { return $a -eq $b } }
        if ($e.Type -eq 'Binary') { return ($cur -replace '[\s,-]', '') -eq ($want -replace '[\s,-]', '') }
        $cur.Trim() -eq $want.Trim()
    } catch { $false }
}
function Test-Writable($e, [string]$v) {   # checked before anything is written, so a typo in the catalogue changes nothing
    if ($v -in '<delete>', '<deletevalue>') { return $true }
    switch ($e.Type) {
        'DWORD' { $n = ConvertTo-Num $v; return $null -ne $n -and $n -le [uint32]::MaxValue }
        'QWORD' { return $null -ne (ConvertTo-Num $v) }
        'Binary' { $h = $v -replace '[\s,-]', ''; return $h.Length -gt 0 -and $h.Length % 2 -eq 0 -and $h -match '^[0-9a-f]+$' }
        { $_ -in 'String', 'ExpandString' } { return $true }
    }
    $false
}
function Set-TweakVal($e, [string]$v) {   # writes (or deletes) one value, then reads it back: Windows may accept a write and ignore it
    $q = Split-Reg $e.Path; if (-not $q.Root -or -not $q.Sub) { return $false }
    $nm = if ($e.Name -eq '(Default)') { '' } else { $e.Name }
    try {
        if ($v -eq '<delete>') { $q.Root.DeleteSubKeyTree($q.Sub, $false) }
        elseif ($v -eq '<deletevalue>') { $k = $q.Root.OpenSubKey($q.Sub, $true); if ($k) { $k.DeleteValue($nm, $false); $k.Dispose() } }
        else {
            $k = $q.Root.CreateSubKey($q.Sub, $true)
            switch ($e.Type) {
                'DWORD' { $k.SetValue($nm, [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32](ConvertTo-Num $v)), 0), 'DWord') }
                'QWORD' { $k.SetValue($nm, [BitConverter]::ToInt64([BitConverter]::GetBytes([uint64](ConvertTo-Num $v)), 0), 'QWord') }
                'Binary' { $k.SetValue($nm, [Convert]::FromHexString(($v -replace '[\s,-]', '')), 'Binary') }
                'ExpandString' { $k.SetValue($nm, $v, 'ExpandString') }
                default { $k.SetValue($nm, $v, 'String') }
            }
            $k.Dispose()
        }
        Test-TweakVal $e $v
    } catch { $false }
}
function Invoke-Tweak($t) {   # applies (or, Mark = 'undo', resets) one setting; all values are checked first, none are rolled back
    $undo = $t.Mark -eq 'undo'
    if ($Demo) { $t.State = if ($undo) { 'off' } else { 'on' }; return $true }
    foreach ($e in $t.Vals) { $v = if ($undo) { $e.Def } else { $e.Rec }; if (-not $v -or -not (Test-Writable $e $v)) { return $false } }
    if ($script:Dry) { return $true }
    foreach ($e in $t.Vals) { if (-not (Set-TweakVal $e $(if ($undo) { $e.Def } else { $e.Rec }))) { return $false } }
    $true
}
function Load-Tweaks {
    if ($null -eq $script:TweakDb) { $f = Join-Path $dataDir 'WinRules.ini'; $script:TweakDb = @(if (Test-Path -LiteralPath $f) { Read-Tweaks $f }) }
    $i = 0
    $app.tweaks = @(@(foreach ($t in $script:TweakDb) {
                if (-not $Demo -and -not (Test-Fits $t)) { continue }
                $t.Mark = $null; $t.Locked = $t.Admin -and -not $script:IsAdmin
                if ($Demo) { if (-not $t.State) { $t.State = if (($i++ % 3) -eq 0) { 'on' } else { 'off' } } }   # invented states: the registry is not read
                else { $t.State = if (@($t.Vals | Where-Object { -not (Test-TweakVal $_ $_.Rec) }).Count) { 'off' } else { 'on' } }
                $t
            }) | Sort-Object Cat, Name)
}
function Clear-Groups { foreach ($g in @($app.tweaks | Where-Object { $_.Mark -and $_.Group } | Group-Object Group)) { $g.Group | Select-Object -Skip 1 | ForEach-Object { $_.Mark = $null } } }   # one row per Group
function Send-SettingChange { if ($Demo -or $script:Dry) { return }; try { Use-Native; $r = [IntPtr]::Zero; [void][RB.Win32]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [IntPtr]::Zero, 'ImmersiveColorSet', 2, 100, [ref]$r) } catch { } }
function Restart-Explorer {   # some settings are read only when Explorer starts; asked for on the result screen
    if ($Demo -or $script:Dry) { return }
    $sid = (Get-Process -Id $PID).SessionId
    foreach ($p in @(Get-Process explorer -ErrorAction SilentlyContinue | Where-Object SessionId -eq $sid)) { try { $p.Kill(); [void]$p.WaitForExit(3000) } catch { } }
    Start-Sleep -Milliseconds 800
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue | Where-Object SessionId -eq $sid)) { Start-Process explorer.exe }
    Write-Log 'restarted Explorer'
}

# ---------- UNINSTALL: Store apps and programs, judged by AppRules.ini (ported from FluentCleaner) ----------
# Windows needs these, whatever a rule file says; the last two are what RetroBoost itself runs in
$mustKeep = '*_cw5n1h2txyewy', 'Microsoft.WindowsStore', 'Microsoft.DesktopAppInstaller', 'Microsoft.SecHealthUI', 'Microsoft.UI.Xaml', 'Microsoft.VCLibs', 'Microsoft.NET.Native', 'Microsoft.WindowsAppRuntime', 'Microsoft.MicrosoftEdge', 'Microsoft.PowerShell', 'Microsoft.WindowsTerminal'
$uninstKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
function Read-AppRules {   # [section] with Action=apps|programs, Safety=Protected|Safe, then Package= / Program= lines
    $rules = [Collections.Generic.List[object]]::new(); $act = ''; $lvl = 0
    $f = Join-Path $dataDir 'AppRules.ini'
    if (Test-Path -LiteralPath $f) {
        foreach ($raw in [IO.File]::ReadLines($f)) {
            $line = $raw.Trim(); if (-not $line -or $line[0] -eq ';') { continue }
            if ($line[0] -eq '[') { $act = ''; $lvl = 0; continue }
            $i = $line.IndexOf('='); if ($i -lt 1) { continue }
            $v = $line.Substring($i + 1).Trim(); $c = $v.IndexOf(' ;'); if ($c -ge 0) { $v = $v.Substring(0, $c).Trim() }
            switch ($line.Substring(0, $i).Trim()) {
                'Action' { $act = $v }
                'Safety' { $lvl = switch ($v) { 'Protected' { 2 } 'Safe' { 1 } default { 0 } } }
                'Package' { if ($v -and $act -eq 'apps') { $rules.Add(@('store', $v, $lvl)) } }
                'Program' { if ($v -and $act -eq 'programs') { $rules.Add(@('program', $v, $lvl)) } }
            }
        }
    }
    , $rules.ToArray()
}
function Test-Pkg([string]$fam, [string]$pat) { if ($pat.StartsWith('*')) { $pat.Length -gt 1 -and $fam.EndsWith($pat.Substring(1), 'OrdinalIgnoreCase') } else { $fam.StartsWith($pat, 'OrdinalIgnoreCase') } }
function Get-Safety($a, $rules) {   # 0 = yours, 1 = suggested (put there to advertise), 2 = protected; protected always wins
    if ($a.Locked -or ($a.Kind -eq 'store' -and @($mustKeep | Where-Object { Test-Pkg $a.Family $_ }).Count) -or ($a.Kind -eq 'program' -and $a.Name -match '^PowerShell \d')) { return 2 }
    $lv = foreach ($x in $rules) {
        if ($x[0] -ne $a.Kind) { continue }
        if ($(if ($a.Kind -eq 'store') { Test-Pkg $a.Family $x[1] } else { $a.Name.IndexOf($x[1], [StringComparison]::OrdinalIgnoreCase) -ge 0 -or $a.Publisher.IndexOf($x[1], [StringComparison]::OrdinalIgnoreCase) -ge 0 })) { $x[2] }
    }
    [int](@($lv) + 0 | Measure-Object -Maximum).Maximum
}
function Load-Apps {   # the programs the Control Panel lists, plus the Store apps the Start menu shows
    if ($Demo) {
        if ($null -eq $app.uapps) {
            $fake = @(   # name, type, safety, publisher (several arrays per line: no leading comma)
                @('Candy Cascade Saga', 'store', 1, 'King of Games'), @('Weather Now', 'store', 1, 'Microsoft Corporation'), @('Solitaire Deluxe', 'store', 1, 'Microsoft Corporation')
                @('Trial Antivirus 360', 'program', 1, 'Trialware Inc.'), @('chatapp', 'program', 0, 'Chat Co.'), @('cloudsync', 'program', 0, 'Cloud Co.'), @('codeeditor', 'program', 0, 'Editor Co.')
                @('gamelauncher', 'program', 0, 'Game Co.'), @('mediaplayer', 'store', 0, 'Media Co.'), @('App Installer', 'store', 2, 'Microsoft Corporation')
                @('Microsoft Store', 'store', 2, 'Microsoft Corporation'), @('NVIDIA Graphics Driver', 'program', 2, 'NVIDIA Corporation'), @('Windows Security', 'store', 2, 'Microsoft Corporation')
            )
            $app.uapps = @(foreach ($f in $fake) {
                    [pscustomobject]@{ Name = $f[0]; Kind = $f[1]; Safety = $f[2]; Publisher = $f[3]; Family = ($f[0] -replace '\W', '') + '_demo'; Quiet = ''; Locked = $false; On = $false; Gone = $false
                        Cmd = $(if ($f[1] -eq 'program') { '"C:\Program Files\{0}\uninstall.exe"' -f $f[0] } else { '' })
                    }
                })
        }
        $app.uapps = @($app.uapps | Where-Object { -not $_.Gone }); foreach ($a in $app.uapps) { $a.On = $false }
        return
    }
    Set-Msg 'SCANNING installed apps and programs ...'; if (-not $script:Quiet) { Redraw }
    $rules = Read-AppRules
    $list = [Collections.Generic.List[object]]::new(); $seen = @{}
    foreach ($place in @(@('LocalMachine', 'Registry64'), @('LocalMachine', 'Registry32'), @('CurrentUser', 'Registry64'))) {
        try { $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey($place[0], $place[1]); $u = $root.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall') } catch { continue }
        if (-not $u) { continue }
        foreach ($id in $u.GetSubKeyNames()) {
            $k = $u.OpenSubKey($id); if (-not $k) { continue }
            $n = "$($k.GetValue('DisplayName'))"; $cmd = "$($k.GetValue('UninstallString'))"
            # hidden from the Control Panel too: system components, updates, parts of a bigger program; -Sandbox lists only rbtest* programs
            if ($n -and $cmd -and -not $seen[$id] -and -not $k.GetValue('SystemComponent') -and $null -eq $k.GetValue('ParentKeyName') -and $null -eq $k.GetValue('ReleaseType') -and -not ($Sandbox -and $n -notlike 'rbtest*')) {
                $seen[$id] = 1
                $list.Add([pscustomobject]@{ Name = $n; Kind = 'program'; Family = $id; Publisher = "$($k.GetValue('Publisher'))"; Cmd = $cmd; Quiet = "$($k.GetValue('QuietUninstallString'))"; Locked = $false; Safety = 0; On = $false; Gone = $false })
            }
            $k.Dispose()
        }
        $u.Dispose(); $root.Dispose()
    }
    if (-not $Sandbox) { try {
        $names = @{}
        foreach ($it in (New-Object -ComObject Shell.Application).NameSpace('shell:AppsFolder').Items()) { $p = "$($it.Path)"; $c = $p.IndexOf('!'); if ($c -gt 0 -and -not $names.ContainsKey($p.Substring(0, $c))) { $names[$p.Substring(0, $c)] = "$($it.Name)" } }
        foreach ($g in @(Get-AppxPackage -ErrorAction Stop | Where-Object { $names.ContainsKey($_.PackageFamilyName) } | Group-Object PackageFamilyName)) {
            $list.Add([pscustomobject]@{ Name = $names[$g.Name]; Kind = 'store'; Family = $g.Name; Publisher = ("$($g.Group[0].Publisher)" -replace '^CN=([^,]+).*$', '$1'); Cmd = ''; Quiet = ''; On = $false; Gone = $false; Safety = 0
                    Locked = [bool]@($g.Group | Where-Object { $_.NonRemovable -or $_.IsFramework -or $_.IsResourcePackage }).Count
                })
        }
    } catch { Set-Msg "Store apps could not be read: $($_.Exception.Message)" 'warn' } }
    foreach ($a in $list) { $a.Safety = Get-Safety $a $rules }
    $app.uapps = @($list | Sort-Object Name)
    if ($app.msgStyle -ne 'warn') { Set-Msg '' }
}
function Test-Gone($a) {   # an uninstaller's exit code says nothing: the list that showed the app decides
    if ($a.Kind -eq 'store') { return -not (Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object PackageFamilyName -eq $a.Family) }
    -not @($uninstKeys | Where-Object { (Get-ItemProperty -LiteralPath "$_\$($a.Family)" -ErrorAction SilentlyContinue).DisplayName }).Count
}
function Invoke-Wait([string]$exe, [string]$argv, [int]$sec) {   # no console window of its own; 0 seconds = wait as long as the user needs
    try {
        $psi = [Diagnostics.ProcessStartInfo]::new($exe, $argv); $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true   # our screen and keyboard stay ours
        $p = [Diagnostics.Process]::Start($psi)
        $p.StandardInput.Close(); $null = $p.StandardOutput.ReadToEndAsync(); $null = $p.StandardError.ReadToEndAsync()   # drained, never shown
        if ($sec) { if (-not $p.WaitForExit($sec * 1000)) { try { $p.Kill() } catch { } } } else { $p.WaitForExit() }
    } catch { }
}
function Remove-App($a) {   # $true once Windows no longer lists it
    if ($Demo) { $a.Gone = $true; return $true }
    if ($a.Safety -ge 2 -or $a.Locked) { return $false }
    if ($script:Dry) { return $true }
    if ($a.Kind -eq 'store') {
        try { foreach ($p in @(Get-AppxPackage -ErrorAction Stop | Where-Object PackageFamilyName -eq $a.Family)) { if (-not ($p.NonRemovable -or $p.IsFramework)) { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop } } } catch { }
        return Test-Gone $a
    }
    # silent ways first, each verified; cmd.exe runs the stored commands as Windows would (and shows UAC when one needs it)
    $steps = [Collections.Generic.List[object]]::new()
    if ($a.Quiet) { $steps.Add(@('cmd.exe', "/c `"$($a.Quiet)`"", 300)) }
    if ($a.Cmd -match 'MsiExec(?:\.exe)?"?\s*/[IX]\s*(\{[0-9A-Fa-f-]{36}\})') { $steps.Add(@('msiexec.exe', "/x $($Matches[1]) /qn /norestart", 300)) }
    $steps.Add(@('cmd.exe', "/c `"$($a.Cmd)`"", 0))   # last: the maker's own uninstaller window, for as long as it takes
    foreach ($s in $steps) { Invoke-Wait $s[0] $s[1] $s[2]; if (Test-Gone $a) { return $true } }
    $false
}

# ---------- AUTO: the windowless run (Task Scheduler) and its schedule ----------
$taskName = 'RetroBoost AutoClean'
function Invoke-Auto {   # BOOST's safe cleaning without a screen: nothing is stopped or trimmed
    Write-Log 'AUTO start'
    Scan-Disk
    $sel = @($app.cats | Where-Object { $_.On -and $_.Ready })
    if ($cfg.boostApps) { Load-Rules; $sel += @(Get-RuleJobs) }
    $freed = 0L
    foreach ($c in $sel) { $b = Invoke-Clean $c; $freed += $b; Write-Log "auto clean $($c.Id): $(Gb $b)" }
    foreach ($s in (Get-Skipped (@($app.cats) + @($app.rules)))) { Write-Log "auto skipped $s" }
    Write-Log ('AUTO done: freed {0}' -f (Gb $freed))
    "RetroBoost AUTO$(if ($script:Dry) { ' (dry-run)' }): freed $(Gb $freed). Log: $logFile"
    if ($Shutdown) {
        Write-Log 'AUTO shutdown in 60 s (run "shutdown /a" to cancel)'
        if (-not $script:Dry -and -not $Demo) { shutdown.exe /s /t 60 /c 'RetroBoost auto-clean is done. Windows shuts down in 60 seconds; run "shutdown /a" to cancel.' }
    }
}
function Set-Schedule([string]$when) {   # off, daily, weekly, logon: a task for your account, no admin needed
    if ($script:Dry) { return 'Could not change the schedule: DRY-RUN is on.' }
    if ($Demo -or $script:Test) { return 'Demo or test: shown here only, no task created.' }
    try {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        if ($when -eq 'off') { return 'Auto-clean switched off: the scheduled task is gone.' }
        $argv = '-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Auto -ConfigDir "{1}"' -f $selfPath, $ConfigDir
        # pwsh as found on PATH (like RetroBoost.cmd): the Store build's own folder carries a version and moves with every update
        $exe = (Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source; if (-not $exe) { $exe = (Get-Process -Id $PID).Path }
        $trg = switch ($when) { 'daily' { New-ScheduledTaskTrigger -Daily -At 12:00 } 'weekly' { New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 12:00 } default { New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME" } }
        $set = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1)
        $null = Register-ScheduledTask -TaskName $taskName -Action (New-ScheduledTaskAction -Execute $exe -Argument $argv) -Trigger $trg -Settings $set -Description 'RetroBoost: cleans safe junk without a window. Change it in RetroBoost > SETTINGS.' -Force -ErrorAction Stop
        Write-Log "schedule: $when"
        "Auto-clean scheduled ($when). Task Scheduler: '$taskName'."
    } catch { "Could not schedule: $($_.Exception.Message)" }
}

# ---------- retro screen buffer ("video RAM") ----------
# ponytail: fixed 78x25 text grid, no live resize; widen the window if it looks clipped
$ESC = [char]27
$CSI = "$ESC["
$COLS = 78; $ROWS = 25
$styleNames = 'norm', 'hi', 'dim', 'title', 'sel', 'ok', 'warn', 'bad', 'frame', 'fillG', 'fillY', 'fillR', 'empty', 'shadow', 'logo', 'logoSh'
$sty = @{}; for ($i = 0; $i -lt $styleNames.Count; $i++) { $sty[$styleNames[$i]] = $i }
$themes = @{   # 256-colour "fg;bg[;bold]"
    blue  = @{ norm = '252;19'; hi = '226;19;1'; dim = '248;19'; title = '16;37'; sel = '16;37'; ok = '46;19;1'; warn = '214;19;1'; bad = '203;19;1'; frame = '87;19'; fillG = '46;19'; fillY = '226;19'; fillR = '203;19'; empty = '24;19'; shadow = '240;16'; logo = '231;19;1'; logoSh = '25;19' }
    green = @{ norm = '40;16'; hi = '118;16;1'; dim = '28;16'; title = '16;40'; sel = '16;40'; ok = '118;16;1'; warn = '190;16;1'; bad = '196;16;1'; frame = '34;16'; fillG = '40;16'; fillY = '190;16'; fillR = '196;16'; empty = '22;16'; shadow = '233;16'; logo = '118;16;1'; logoSh = '22;16' }
    amber = @{ norm = '214;16'; hi = '226;16;1'; dim = '130;16'; title = '16;214'; sel = '16;214'; ok = '214;16;1'; warn = '226;16;1'; bad = '203;16;1'; frame = '172;16'; fillG = '214;16'; fillY = '226;16'; fillR = '203;16'; empty = '94;16'; shadow = '233;16'; logo = '220;16;1'; logoSh = '94;16' }
}
function Set-Theme([string]$name) {
    $tm = $themes[$name]
    $script:Sgr = foreach ($n in $styleNames) { $p = $tm[$n] -split ';'; "${CSI}0;$(if ($p[2]) { '1;' })38;5;$($p[0]);48;5;$($p[1])m" }
}
$cellC = [char[][]]::new($ROWS); $cellS = [int[][]]::new($ROWS)
for ($r = 0; $r -lt $ROWS; $r++) { $cellC[$r] = [char[]]::new($COLS); $cellS[$r] = [int[]]::new($COLS) }
function Clear-Buf { for ($r = 0; $r -lt $ROWS; $r++) { [Array]::Fill($cellC[$r], [char]' '); [Array]::Fill($cellS[$r], 0) } }
function Put([int]$r, [int]$c, [string]$text, [int]$style = 0) {
    if ($r -lt 0 -or $r -ge $ROWS) { return }
    $row = $cellC[$r]; $sr = $cellS[$r]
    for ($i = 0; $i -lt $text.Length; $i++) { $x = $c + $i; if ($x -ge 0 -and $x -lt $COLS) { $row[$x] = $text[$i]; $sr[$x] = $style } }
}
function Show-Buf {
    if ($script:Test) {
        if ($Dump) {   # structured copy of the frame, for tools/Render-Screenshots.ps1
            $pal = $themes[$cfg.theme]
            $script:Dumped.Add([pscustomobject]@{
                    screen = $app.screen; theme = $cfg.theme
                    palette = @($styleNames | ForEach-Object { $q = $pal[$_] -split ';'; [pscustomobject]@{ fg = [int]$q[0]; bg = [int]$q[1]; bold = [bool]$q[2] } })
                    rows = @(0..($ROWS - 1) | ForEach-Object { -join $cellC[$_] })
                    styles = @(0..($ROWS - 1) | ForEach-Object { -join ($cellS[$_] | ForEach-Object { '{0:x}' -f $_ }) })
                })
        }
        Write-Host ('--- frame {0} [{1}] ---' -f (++$script:Frame), $app.screen)
        for ($r = 0; $r -lt $ROWS; $r++) { Write-Host (-join $cellC[$r]).TrimEnd() }
        return
    }
    try { $offC = [Math]::Max(0, [int](([Console]::WindowWidth - $COLS) / 2)); $offR = [Math]::Max(0, [int](([Console]::WindowHeight - $ROWS) / 2)) } catch { $offC = 0; $offR = 0 }
    $sb = [Text.StringBuilder]::new()
    for ($r = 0; $r -lt $ROWS; $r++) {
        [void]$sb.Append("${CSI}$($r + 1 + $offR);$($offC + 1)H")
        $cur = -1; $row = $cellC[$r]; $sr = $cellS[$r]
        for ($x = 0; $x -lt $COLS; $x++) {
            if ($sr[$x] -ne $cur) { $cur = $sr[$x]; [void]$sb.Append($script:Sgr[$cur]) }
            [void]$sb.Append($row[$x])
        }
    }
    [Console]::Write($sb.Append("${CSI}0m").ToString())
}
function Box([int]$r, [int]$c, [int]$h, [int]$w, [string]$title = '') {
    Put $r $c ('╔' + ('═' * ($w - 2)) + '╗') $sty.frame
    for ($i = 1; $i -lt $h - 1; $i++) { Put ($r + $i) $c ('║' + (' ' * ($w - 2)) + '║') $sty.frame }
    Put ($r + $h - 1) $c ('╚' + ('═' * ($w - 2)) + '╝') $sty.frame
    if ($title) { Put $r ($c + 3) $title $sty.hi }
}
function Gauge([int]$r, [int]$c, [string]$label, [double]$pct, [string]$info, [int]$w = 30) {
    $pct = [Math]::Max(0, [Math]::Min(100, $pct)); $n = [int][Math]::Round($pct / 100 * $w)
    $fill = if ($pct -ge 85) { $sty.fillR } elseif ($pct -ge 60) { $sty.fillY } else { $sty.fillG }
    Put $r $c $label $sty.dim
    Put $r ($c + 8) ('█' * $n) $fill
    Put $r ($c + 8 + $n) ('░' * ($w - $n)) $sty.empty
    Put $r ($c + 9 + $w) ('{0,3:N0}%' -f $pct) $sty.hi
    Put $r ($c + 16 + $w) $info $sty.norm
}
function Dialog([string]$title, $lines, [string]$prompt) {
    $lines = @($lines); $w = 68; $h = $lines.Count + 5
    $r = [Math]::Max(1, [int](($ROWS - $h) / 2)); $c = [int](($COLS - $w) / 2)
    for ($yy = 1; $yy -lt $ROWS - 1; $yy++) { [Array]::Fill($cellS[$yy], $sty.dim) }   # dim the screen behind the dialog
    Put ($r + $h) ($c + 2) (' ' * $w) $sty.shadow
    for ($i = 1; $i -le $h; $i++) { Put ($r + $i) ($c + $w) '  ' $sty.shadow }
    Box $r $c $h $w $title
    for ($i = 0; $i -lt $lines.Count; $i++) { Put ($r + 2 + $i) ($c + 3) (Fit $lines[$i][0] ($w - 6)) $sty[$lines[$i][1]] }
    Put ($r + $h - 2) ($c + 3) $prompt $sty.hi
}

$font = @{
    R = '██ ', '█ █', '██ ', '█ █', '█ █'
    E = '███', '█  ', '██ ', '█  ', '███'
    T = '███', ' █ ', ' █ ', ' █ ', ' █ '
    O = '███', '█ █', '█ █', '█ █', '███'
    B = '██ ', '█ █', '██ ', '█ █', '██ '
    S = '███', '█  ', '███', '  █', '███'
}
function Draw-Logo([int]$r, [int]$c, [string]$word) {
    foreach ($layer in @(@(1, 1, 'logoSh'), @(0, 0, 'logo'))) {   # drop shadow first, then the letters on top
        for ($row = 0; $row -lt 5; $row++) {
            $line = ($word.ToCharArray() | ForEach-Object { $font["$_"][$row] }) -join ' '
            for ($i = 0; $i -lt $line.Length; $i++) {
                if ($line[$i] -ne ' ') { Put ($r + $row + $layer[0]) ($c + $i + $layer[1]) $(if ($layer[2] -eq 'logoSh') { '▒' } else { [string]$line[$i] }) $sty[$layer[2]] }
            }
        }
    }
}
function Draw-Chrome([string]$hint) {
    Clear-Buf
    Put 0 0 (Fit '  RETROBOOST v2.0   ::   PC TUNE-UP UTILITY' $COLS) $sty.title
    if ($Demo) { Put 0 ($COLS - 8) ' DEMO ' $sty.warn } elseif ($script:Dry) { Put 0 ($COLS - 11) ' DRY-RUN ' $sty.warn } elseif ($script:IsAdmin) { Put 0 ($COLS - 9) ' ADMIN ' $sty.warn }
    Put ($ROWS - 1) 0 (Fit "  $hint" $COLS) $sty.title
    if ($app.msg) { Put ($ROWS - 2) 2 (Fit $app.msg ($COLS - 4)) $sty[$app.msgStyle] }
}

# ---------- app state and screens ----------
$app = @{ screen = 'main'; back = 'main'; sel = 0; msg = ''; msgStyle = 'dim'; quit = $false; sys = $null; cpu = 0
    cats = @(); dsel = 0; procs = @(); plist = @(); psel = 0; ptop = 0; psort = 'mem'; marks = @{}; ssel = 0; log = $null; pct = 0; title = ''; res = $null
    rules = $null; tweaks = @(); uapps = $null; items = @(); lsel = 0; ltop = 0; acDirty = $false }   # items/lsel/ltop: the list on APP CLEAN, TWEAKS or UNINSTALL
$menu = @(   # two columns of five: the first five on the left
    @{ Key = 'B'; Name = 'BOOST NOW'; Desc = 'clean safe junk, trim RAM, close your kill-list programs' }
    @{ Key = 'D'; Name = 'DISK CLEAN'; Desc = 'temp files, package and browser caches, crash dumps' }
    @{ Key = 'A'; Name = 'APP CLEAN'; Desc = '4,000+ app cleaners from winapp2.ini, ticked with care' }
    @{ Key = 'R'; Name = 'RAM TRIM'; Desc = 'free memory, see the biggest memory users' }
    @{ Key = 'P'; Name = 'PROCESSES'; Desc = 'stop programs now, build your kill list' }
    @{ Key = 'T'; Name = 'TWEAKS'; Desc = 'switch off Windows ads, tips, telemetry and AI extras (undo too)' }
    @{ Key = 'U'; Name = 'UNINSTALL'; Desc = 'remove bloatware, Store apps and programs you do not use' }
    @{ Key = 'S'; Name = 'SETTINGS'; Desc = 'theme, sound, safety switches, auto-clean schedule' }
    @{ Key = 'H'; Name = 'HELP'; Desc = 'what every screen does, and how RetroBoost stays safe' }
    @{ Key = 'Q'; Name = 'QUIT'; Desc = 'back to Windows' }
)
function Redraw { & "Draw-$($app.screen)"; Show-Buf }

function Draw-main {
    Draw-Chrome '↑↓←→ move    ENTER select    letter = hotkey    F1 help'
    Draw-Logo 2 19 'RETROBOOST'
    Put 8 0 (Center '░▒▓  CLEAN  ·  TWEAK  ·  UNINSTALL  ·  TRIM RAM  ·  STOP PROCESSES  ▓▒░') $sty.dim
    Box 9 2 6 74 ' SYSTEM STATUS '
    $y = $app.sys; $dUsed = $y.DiskTotal - $y.DiskFree; $rUsed = $y.RamTotal - $y.RamFree
    Gauge 10 4 'DISK C:' (100 * $dUsed / $y.DiskTotal) ('{0:N1} of {1:N1} GB used' -f ($dUsed / 1GB), ($y.DiskTotal / 1GB))
    Gauge 11 4 'RAM' (100 * $rUsed / $y.RamTotal) ('{0:N1} of {1:N1} GB used' -f ($rUsed / 1GB), ($y.RamTotal / 1GB))
    Gauge 12 4 'CPU' $app.cpu ('{0}% busy' -f $app.cpu)
    Put 13 4 ('Kill list: {0}   ·   Free disk: {1}   ·   Free RAM: {2}' -f $cfg.killList.Count, (Gb $y.DiskFree), (Mb $y.RamFree)) $sty.dim
    Box 15 2 8 74 ' MAIN MENU '
    for ($i = 0; $i -lt $menu.Count; $i++) {
        $m = $menu[$i]; $row = 16 + $i % 5; $col = 4 + 36 * [int][Math]::Floor($i / 5)
        if ($i -eq $app.sel) { Put $row ($col - 1) (Fit (' [{0}]  {1}' -f $m.Key, $m.Name) 34) $sty.sel; continue }
        Put $row $col ('[{0}]' -f $m.Key) $sty.norm; Put $row ($col + 1) $m.Key $sty.hi
        Put $row ($col + 5) $m.Name $(if ($i -eq 0) { $sty.hi } else { $sty.norm })
    }
    Put 21 4 (Fit ('» ' + $menu[$app.sel].Desc) 70) $sty.dim
}

# ---------- the three list screens (APP CLEAN, TWEAKS, UNINSTALL) share one scrolling list ----------
function Set-Items($groups) {   # $groups: (name, members) pairs in display order -> a header row per group, then its members
    $app.items = @(foreach ($g in $groups) { if (@($g[1]).Count) { [pscustomobject]@{ Head = $true; Name = $g[0]; Members = @($g[1]) }; $g[1] } })
    $app.lsel = [Math]::Min(1, [Math]::Max(0, $app.items.Count - 1)); $app.ltop = 0
}
function Move-Sel([string]$k) {   # $true when the key moved the selection
    $n = $app.items.Count; if (-not $n) { return $false }
    switch ($k) {
        'UP' { $app.lsel = [Math]::Max(0, $app.lsel - 1) }
        'DOWN' { $app.lsel = [Math]::Min($n - 1, $app.lsel + 1) }
        'PGUP' { $app.lsel = [Math]::Max(0, $app.lsel - 13) }
        'PGDN' { $app.lsel = [Math]::Min($n - 1, $app.lsel + 13) }
        'HOME' { $app.lsel = 0 }
        'END' { $app.lsel = $n - 1 }
        'RIGHT' { for ($i = $app.lsel + 1; $i -lt $n; $i++) { if ($app.items[$i].Head) { $app.lsel = $i; break } } }   # next group
        'LEFT' { for ($i = $app.lsel - 1; $i -ge 0; $i--) { if ($app.items[$i].Head) { $app.lsel = $i; break } } }    # previous group
        default { return $false }
    }
    $true
}
function Draw-List([scriptblock]$line) {   # rows 5..17; $line turns an item into @(text, style name)
    $vis = 13
    if ($app.lsel -lt $app.ltop) { $app.ltop = $app.lsel } elseif ($app.lsel -ge $app.ltop + $vis) { $app.ltop = $app.lsel - $vis + 1 }
    for ($i = 0; $i -lt $vis; $i++) {
        $idx = $app.ltop + $i; if ($idx -ge $app.items.Count) { break }
        $x = $app.items[$idx]
        $t = if ($x.Head) { @(('▓▒░ {0}  ({1})' -f $x.Name.ToUpper(), @($x.Members).Count), 'hi') } else { & $line $x }
        Put (5 + $i) 4 (Fit $t[0] 72) $(if ($idx -eq $app.lsel) { $sty.sel } else { $sty[$t[1]] })
    }
    if ($app.items.Count -gt $vis) { Put 4 62 (' {0}/{1} ' -f ($app.lsel + 1), $app.items.Count) $sty.dim }
}
function Put-Info($lines) { $i = 0; foreach ($l in @($lines) | Select-Object -First 3) { Put (19 + $i) 4 (Fit $l[0] 72) $sty[$l[1]]; $i++ } }   # rows 19..21

function Draw-appclean {
    Draw-Chrome '↑↓ move  ←→ group  SPACE tick  A safe set  N none  S scan  ENTER clean  ESC'
    Box 1 1 22 76 (' APP CLEAN  -  {0} app cleaners match this PC ' -f [int]$app.rules.Count)
    Put 3 4 'SEL  CLEANER' $sty.dim; Put 3 53 '    FOUND' $sty.dim; Put 3 64 'STATUS' $sty.dim
    Put 4 3 ('─' * 72) $sty.frame
    Draw-List {
        param($r)
        $st = if (-not $r.Ready) { $r.Why } elseif ($r.Warn) { 'warning' } elseif ($r.Scanned -and -not $r.Bytes -and -not @($r.RegList).Count) { 'nothing' } elseif ($r.Scanned) { 'ready' } else { '' }
        $sz = if ($r.Scanned) { (Sz $r.Bytes) + $(if (@($r.RegList).Count) { '+' }) } else { '?' }
        $mk = if (-not $r.Ready) { '[!]' } elseif ($r.On) { '[x]' } else { '[ ]' }
        @(('{0}  {1} {2,9}  {3}' -f $mk, (Fit $r.Name 43), $sz, $st), $(if (-not $r.Ready) { 'dim' } elseif ($r.Warn) { 'warn' } elseif ($r.On) { 'norm' } else { 'dim' }))
    }
    if ($null -ne $app.rules -and -not $app.rules.Count) { Put 6 6 'No app cleaner matches this PC (or data\Winapp2.ini is missing).' $sty.dim }
    $on = @($app.rules | Where-Object { $_.On -and $_.Ready }); $todo = @($on | Where-Object { -not $_.Scanned }).Count
    Put 18 4 ('TICKED: {0} cleaner(s), {1} found{2}' -f $on.Count, (Sz ([long]($on | Where-Object Scanned | Measure-Object Bytes -Sum).Sum)), $(if ($todo) { "   (S scans the other $todo)" })) $sty.hi
    $x = $app.items[$app.lsel]
    if (-not $x) { return }
    if ($x.Head) { Put-Info @(@('SPACE ticks or clears every cleaner in this group.', 'dim'), @('A + after a size means registry entries are cleaned too.', 'dim')); return }
    $info = @(foreach ($l in @(Wrap $x.Warn 72)) { , @($l, 'warn') }) + @(foreach ($l in @($x.Files) + @($x.Regs)) { , @("cleans  $l", 'dim') })
    if (-not $x.Ready) { $info = @(, @("Close $($x.Why.Substring(6)) first, then come back: its files are in use.", 'warn')) + $info }
    Put-Info $info
}

function Draw-tweaks {
    Draw-Chrome '↑↓ move  ←→ group  SPACE tick/undo  A recommended  N none  ENTER apply  ESC'
    Box 1 1 22 76 (' TWEAKS  -  {0} settings for Windows {1} ' -f [int]$app.tweaks.Count, $(if ($win11) { '11' } else { '10' }))
    Put 3 4 'SEL  SETTING' $sty.dim; Put 3 66 'NOW' $sty.dim
    Put 4 3 ('─' * 72) $sty.frame
    Draw-List {
        param($t)
        $mk = if ($t.Locked) { '[A]' } elseif ($t.Mark -eq 'undo') { '[u]' } elseif ($t.Mark) { '[x]' } else { '[ ]' }
        $now = if ($t.State -eq 'on') { 'ON' } else { 'off' }
        @(('{0}  {1}  {2}' -f $mk, (Fit $t.Name 55), $now), $(if ($t.Locked) { 'dim' } elseif ($t.Mark) { 'hi' } elseif ($t.State -eq 'on') { 'ok' } else { 'norm' }))
    }
    $on = @($app.tweaks | Where-Object State -eq 'on').Count; $ap = @($app.tweaks | Where-Object Mark -eq 'apply').Count; $un = @($app.tweaks | Where-Object Mark -eq 'undo').Count
    Put 18 4 ('ON: {0}   ·   TO APPLY: {1}   ·   TO UNDO: {2}   ·   [A] needs admin: {3}' -f $on, $ap, $un, @($app.tweaks | Where-Object Locked).Count) $sty.hi
    $x = $app.items[$app.lsel]
    if (-not $x) { return }
    if ($x.Head) { Put-Info @(@('SPACE ticks every setting of this group that is still off.', 'dim'), @('On a row that is ON, SPACE marks it [u]: put back as Windows had it.', 'dim')); return }
    $tail = switch ($x.Restart) { 'explorer' { ' (shows after an Explorer restart)' } 'system' { ' (shows after a Windows restart)' } default { '' } }
    $info = @(foreach ($l in @(Wrap ($x.Desc + $tail) 72)) { , @($l, 'norm') })
    if ($x.Locked) { $info = @(, @('[A] Needs admin: right-click RetroBoost.cmd > Run as administrator.', 'warn')) + $info }
    Put-Info $info
}

function Draw-uninst {
    Draw-Chrome '↑↓ move  ←→ group  SPACE tick  A suggested  N none  ENTER remove  ESC back'
    Box 1 1 22 76 (' UNINSTALL  -  {0} apps and programs ' -f [int]$app.uapps.Count)
    Put 3 4 'SEL  NAME' $sty.dim; Put 3 56 'TYPE' $sty.dim; Put 3 65 'VERDICT' $sty.dim
    Put 4 3 ('─' * 72) $sty.frame
    Draw-List {
        param($a)
        $mk = if ($a.Safety -ge 2) { '[#]' } elseif ($a.On) { '[x]' } else { '[ ]' }
        $v = switch ($a.Safety) { 2 { 'PROTECTED' } 1 { 'suggested' } default { 'yours' } }
        @(('{0}  {1}  {2,-7}  {3}' -f $mk, (Fit $a.Name 45), $(if ($a.Kind -eq 'store') { 'STORE' } else { 'PROGRAM' }), $v), $(if ($a.Safety -ge 2) { 'dim' } elseif ($a.On) { 'hi' } else { 'norm' }))
    }
    Put 18 4 ('TICKED: {0} app(s)   ·   nothing is pre-ticked   ·   # = locked' -f @($app.uapps | Where-Object On).Count) $sty.hi
    $x = $app.items[$app.lsel]
    if (-not $x -or $x.Head) { Put-Info @(@('Suggested = put there to advertise or sell (data\AppRules.ini).', 'dim'), @('Read the list before you tick: RetroBoost cannot undo an uninstall.', 'dim')); return }
    Put-Info @(@("Publisher: $($x.Publisher)", 'norm'), @($(if ($x.Kind -eq 'store') { "Package: $($x.Family)   (reinstall from the Microsoft Store)" } else { "Uninstaller: $($x.Cmd)" }), 'dim'), @($(if ($x.Safety -ge 2) { 'Locked: Windows or RetroBoost needs it.' } elseif ($x.Kind -eq 'program') { 'Its own uninstaller may open a window: finish it there.' } else { '' }), 'dim'))
}

function Draw-disk {
    Draw-Chrome '↑↓ move  SPACE tick  A defaults  N none  ENTER clean  W Windows  ESC back'
    Box 1 1 22 76 ' DISK CLEAN  -  tick what to delete '
    Put 3 4 'SEL  WHAT' $sty.dim; Put 3 57 'SIZE' $sty.dim; Put 3 63 'STATUS' $sty.dim
    Put 4 3 ('─' * 72) $sty.frame
    for ($i = 0; $i -lt $app.cats.Count; $i++) {
        $c = $app.cats[$i]; $row = 5 + $i
        $mark = if (-not $c.Ready) { '[!]' } elseif ($c.On) { '[x]' } else { '[ ]' }
        $status = if ($c.Ready) { 'ready' } else { $c.Why }
        $line = '{0}  {1}  {2,9}  {3}' -f $mark, (Fit $c.Name 41), (Gb $c.Bytes), (Fit $status 13)
        $st = if ($i -eq $app.dsel) { $sty.sel } elseif (-not $c.Ready) { $sty.dim } elseif ($c.On) { $sty.norm } else { $sty.dim }
        Put $row 4 (Fit $line 72) $st
    }
    $sel = @($app.cats | Where-Object { $_.On -and $_.Ready })
    Put 14 4 ('TICKED: {0} item(s), {1}' -f $sel.Count, (Gb ($sel | Measure-Object Bytes -Sum).Sum)) $sty.hi
    Put 16 4 'Only junk that comes back by itself is listed: caches, temp files,' $sty.dim
    Put 17 4 'installer downloads, crash dumps. The Recycle Bin and GPU caches' $sty.dim
    Put 18 4 'start unticked.' $sty.dim
    Put 19 4 '[!] = cannot run now (close the named app) or nothing to clean.' $sty.dim
    Put 20 4 "Windows' own junk (setup logs, Update cache, old drivers): press W." $sty.dim
}

function Draw-ram {
    Draw-Chrome 'T trim now    ESC back'
    Box 1 1 22 76 ' RAM TRIM '
    $y = $app.sys; $rUsed = $y.RamTotal - $y.RamFree
    Gauge 3 4 'RAM' (100 * $rUsed / $y.RamTotal) ('{0:N1} of {1:N1} GB used' -f ($rUsed / 1GB), ($y.RamTotal / 1GB))
    Put 5 4 ('Available now: {0}' -f (Mb $y.RamFree)) $sty.hi
    Put 7 4 'BIGGEST MEMORY USERS' $sty.dim; Put 7 59 '    MEMORY' $sty.dim
    $top = @($app.procs | Sort-Object Bytes -Descending | Select-Object -First 10); $max = [Math]::Max(1L, [long]($top | Select-Object -First 1).Bytes)
    for ($i = 0; $i -lt $top.Count; $i++) {
        $p = $top[$i]; $row = 8 + $i; $n = [int][Math]::Round(24 * $p.Bytes / $max)
        Put $row 4 (Fit $p.Name 22) $sty.norm
        Put $row 27 ('x{0}' -f $p.N) $sty.dim
        Put $row 33 ('█' * $n) $sty.fillG; Put $row (33 + $n) ('░' * (24 - $n)) $sty.empty
        Put $row 59 ('{0,10}' -f (Mb $p.Bytes)) $sty.norm
    }
    Put 19 4 'T asks Windows to page out idle memory. The relief is temporary:' $sty.dim
    Put 20 4 'Windows refills it when programs need it. Closing heavy programs' $sty.dim
    Put 21 4 'frees RAM for real.' $sty.dim
}

function Draw-procs {
    Draw-Chrome '↑↓ move  SPACE mark  K kill list  X stop  F force  S sort  ESC back'
    Box 1 1 22 76 ' PROCESSES  -  grouped by program name '
    Put 3 4 'MK  KL  PROGRAM' $sty.dim; Put 3 38 '   N' $sty.dim; Put 3 43 '    MEMORY' $sty.dim; Put 3 56 'TYPE' $sty.dim
    Put 4 3 ('─' * 72) $sty.frame
    $vis = 14
    if ($app.psel -lt $app.ptop) { $app.ptop = $app.psel } elseif ($app.psel -ge $app.ptop + $vis) { $app.ptop = $app.psel - $vis + 1 }
    for ($i = 0; $i -lt $vis; $i++) {
        $idx = $app.ptop + $i; if ($idx -ge $app.plist.Count) { break }
        $p = $app.plist[$idx]; $row = 5 + $i
        $mk = if ($app.marks.ContainsKey($p.Name)) { 'x' } else { ' ' }
        $kl = if ($p.Prot) { '#' } elseif ($cfg.killList -contains $p.Name) { '*' } else { ' ' }
        $type = if ($p.Prot) { 'PROTECTED' } elseif ($p.Win) { 'WINDOW' } else { 'BACKGROUND' }
        $line = '[{0}]  {1}   {2} {3,3} {4,12}   {5}' -f $mk, $kl, (Fit $p.Name 24), $p.N, (Mb $p.Bytes), $type
        $st = if ($idx -eq $app.psel) { $sty.sel } elseif ($p.Prot) { $sty.dim } elseif ($kl -eq '*') { $sty.hi } else { $sty.norm }
        Put $row 4 (Fit $line 71) $st
    }
    Put 20 4 ('marked: {0}   kill list: {1}   sort: {2}   (# protected, * on kill list)' -f $app.marks.Count, $cfg.killList.Count, $(if ($app.psort -eq 'mem') { 'memory' } else { 'name' })) $sty.dim
}

function Draw-settings {
    Draw-Chrome '↑↓ move   ENTER or ←→ change   DEL remove from kill list   ESC back'
    Box 1 1 22 76 ' SETTINGS '
    # not named $rows: PowerShell is case-insensitive and callees see their caller's variables, so it would shadow $ROWS
    $opts = @(   # leading commas keep each option an array of its own
        , @('THEME', $cfg.theme.ToUpper(), 'blue, green or amber phosphor')
        , @('SOUND', $(if ($cfg.sound) { 'ON' } else { 'OFF' }), 'retro beeps')
        , @('CONFIRM BOOST', $(if ($cfg.confirm) { 'ON' } else { 'OFF' }), 'OFF = one keypress does everything')
        , @('DRY-RUN', $(if ($script:Dry) { 'ON' } else { 'OFF' }), 'ON = nothing really changes (this session)')
        , @('BOOST+APP CLEAN', $(if ($cfg.boostApps) { 'ON' } else { 'OFF' }), 'ON = BOOST also runs your APP CLEAN ticks')
        , @('AUTO-CLEAN', $cfg.schedule.ToUpper(), 'scheduled safe clean (12:00), no window')
    )
    for ($i = 0; $i -lt $opts.Count; $i++) {
        $line = ' {0}  < {1} >  {2}' -f (Fit $opts[$i][0] 15), (Fit $opts[$i][1] 6), $opts[$i][2]
        $st = if ($i -eq $app.ssel) { $sty.sel } else { $sty.norm }
        Put (3 + $i) 3 (Fit $line 72) $st
    }
    Put 10 4 'KILL LIST: BOOST closes these programs (add them with K on PROCESSES)' $sty.hi
    if (-not $cfg.killList.Count) { Put 11 6 '(empty: nothing is stopped until you add programs)' $sty.dim }
    for ($i = 0; $i -lt [Math]::Min(8, $cfg.killList.Count); $i++) {
        $n = $cfg.killList[$i]; $idx = 6 + $i
        $line = '  {0}{1}' -f $n, $(if ($n.ToLower() -in $protectedNames) { '   (protected, never stopped)' })
        Put (11 + $i) 3 (Fit $line 72) $(if ($idx -eq $app.ssel) { $sty.sel } else { $sty.norm })
    }
    Put 20 4 (Fit $(if ($Demo) { 'Demo mode: nothing is written, deleted or stopped.' } else { "Log: $logFile" }) 72) $sty.dim
    Put 21 4 (Fit ('Own rules: {0}\custom\*.ini  ·  exclusions: {1}' -f $ConfigDir.Replace($env:LOCALAPPDATA, '%LOCALAPPDATA%'), $cfg.exclude.Count) 72) $sty.dim
}

function Draw-help {
    Draw-Chrome 'any key = back'
    Box 1 1 22 76 ' HELP '
    $t = @(   # leading commas keep each line an array of its own
        , @('BOOST NOW   safe junk + RAM trim + your kill list (+ APP CLEAN if on).', 'hi')
        , @('DISK CLEAN  temp files older than a day, package and browser caches,', 'norm')
        , @('            installer downloads, crash dumps. Recycle Bin: unticked.', 'norm')
        , @('APP CLEAN   4,000+ winapp2.ini cleaners. Only cache, temp and log rules', 'norm')
        , @('            start ticked; history, cookies and sessions are yours to', 'norm')
        , @('            tick. Your files and Windows folders are never touched.', 'norm')
        , @('TWEAKS      switch off ads, tips, telemetry. A ticked ON row is undone.', 'norm')
        , @('            [A] rows need RetroBoost started as administrator.', 'norm')
        , @('UNINSTALL   Store apps and programs. Nothing is pre-ticked; Windows', 'norm')
        , @('            parts are locked (#). Store apps can be reinstalled.', 'norm')
        , @('RAM TRIM    pages out idle memory: temporary relief, not magic.', 'norm')
        , @('PROCESSES   K kill list, X stop (asks politely), F force (work lost).', 'norm')
        , @('SAFETY      A plan screen comes before every action. DRY-RUN changes', 'hi')
        , @('            nothing. Windows, security tools and this terminal are', 'norm')
        , @('            protected. Everything is logged (see SETTINGS).', 'norm')
        , @('AUTO        RetroBoost.cmd -Auto cleans without a window; SETTINGS >', 'hi')
        , @('            AUTO-CLEAN schedules it. Rules and ideas: FluentCleaner,', 'norm')
        , @('            winapp2.ini (see THIRD-PARTY-NOTICES.md). F1 = this page.', 'norm')
    )
    for ($i = 0; $i -lt $t.Count; $i++) { Put (3 + $i) 4 $t[$i][0] $sty[$t[$i][1]] }
}

function Draw-run {
    Draw-Chrome ' working... please wait'
    Box 3 4 18 70 " $($app.title) "
    $n = [int]($app.pct / 100 * 50)
    Put 5 8 'PROGRESS' $sty.dim
    Put 5 17 ('█' * $n) $sty.fillG; Put 5 (17 + $n) ('░' * (50 - $n)) $sty.empty; Put 5 68 ('{0,3}%' -f $app.pct) $sty.hi
    $i = 0; foreach ($l in $app.log) { Put (7 + $i) 8 (Fit $l[1] 64) $sty[$l[0]]; $i++ }
}

function Draw-result {
    $x = $app.res
    Draw-Chrome $(if ($x.Restart -contains 'explorer' -and -not $x.Dry) { 'X = restart Explorer now      any other key = continue' } else { 'any key = continue' })
    Box 3 4 18 70 $(if ($x.Dry) { ' RESULT  (dry-run: nothing changed) ' } else { ' RESULT ' })
    $dd = $x.DiskAfter - $x.DiskBefore; $rd = $x.RamAfter - $x.RamBefore; $y = 5
    $line = { param($label, $text, $style) Put $y 8 $label $sty.dim; Put $y 20 (Fit $text 52) $sty[$style]; $y++ }   # dot-sourced, so $y moves on
    if ($x.Cleaned) {
        Put $y 8 'DISK FREE' $sty.dim; Put $y 20 ('{0}  ->  {1}' -f (Gb $x.DiskBefore), (Gb $x.DiskAfter)) $sty.norm
        if (-not $x.Dry) { Put $y 52 ('{0}{1}' -f $(if ($dd -ge 0) { '+' } else { '-' }), (Gb ([Math]::Abs($dd)))) $sty.ok }
        Put ($y + 1) 8 $(if ($x.Dry) { 'WOULD FREE' } else { 'CLEANED' }) $sty.dim; Put ($y + 1) 20 ('{0} reported by the cleaners' -f (Gb $x.Freed)) $sty.hi
        $y += 3
    }
    if ($x.Trimmed -or $x.Closed.Count) {
        Put $y 8 'RAM FREE' $sty.dim; Put $y 20 ('{0}  ->  {1}' -f (Mb $x.RamBefore), (Mb $x.RamAfter)) $sty.norm
        if (-not $x.Dry) { Put $y 52 ('{0}{1}' -f $(if ($rd -ge 0) { '+' } else { '-' }), (Mb ([Math]::Abs($rd)))) $sty.ok }
        Put ($y + 1) 20 'temporary: Windows refills it on demand' $sty.dim
        $y += 3
    }
    if ($x.Closed.Count) { . $line $(if ($x.Dry) { 'WOULD STOP' } else { 'STOPPED' }) ($x.Closed -join ', ') 'hi' }
    if ($x.Stuck.Count) { . $line 'STILL OPEN' (($x.Stuck -join ', ') + '  (a window is waiting for you)') 'warn' }
    if ($x.Skipped.Count) { . $line 'SKIPPED' ($x.Skipped -join '; ') 'warn' }
    if ($x.Tweaked -or $x.Undone) { . $line $(if ($x.Dry) { 'WOULD SET' } else { 'TWEAKS' }) ('{0} applied, {1} undone' -f $x.Tweaked, $x.Undone) 'hi' }
    if ($x.TwFail.Count) { . $line 'NOT SET' ($x.TwFail -join ', ') 'warn' }
    if ($x.Restart.Count -and -not $x.Dry) { . $line 'RESTART' $(if ($x.Restart -contains 'system') { 'restart Windows to finish' } else { 'press X to restart Explorer' }) 'warn' }
    if ($x.Removed.Count) { . $line $(if ($x.Dry) { 'WOULD REMOVE' } else { 'REMOVED' }) ('{0}: {1}' -f $x.Removed.Count, ($x.Removed -join ', ')) 'hi' }
    if ($x.RmFail.Count) { . $line 'STILL THERE' ($x.RmFail -join ', ') 'warn' }
    Put 17 8 'LOG' $sty.dim; Put 17 20 (Fit $logFile 52) $sty.dim
    if ($x.Trimmed) { Put 18 8 'Closing heavy programs frees RAM for real.' $sty.dim }
}

# ---------- keys ----------
function Read-Key([int]$tickMs = 0) {
    if ($script:KeyQ) { if ($script:KeyQ.Count) { return $script:KeyQ.Dequeue().ToUpper() } else { return 'EOF' } }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not [Console]::KeyAvailable) { Start-Sleep -Milliseconds 25; if ($tickMs -gt 0 -and $sw.ElapsedMilliseconds -ge $tickMs) { return 'TICK' } }
    $k = [Console]::ReadKey($true)
    if ($k.Key -eq 'C' -and ($k.Modifiers -band [ConsoleModifiers]::Control)) { return 'Q' }   # Ctrl+C asks to quit
    switch ($k.Key) {
        'UpArrow' { 'UP' } 'DownArrow' { 'DOWN' } 'LeftArrow' { 'LEFT' } 'RightArrow' { 'RIGHT' } 'Enter' { 'ENTER' } 'Escape' { 'ESC' }
        'Spacebar' { 'SPACE' } 'Tab' { 'TAB' } 'PageUp' { 'PGUP' } 'PageDown' { 'PGDN' } 'Home' { 'HOME' } 'End' { 'END' } 'Delete' { 'DEL' } 'F1' { 'F1' }
        default { "$($k.KeyChar)".ToUpper() }
    }
}

function Open-Screen([string]$name) {
    $app.msg = ''; $app.screen = $name; $app.back = $name
    switch ($name) {
        'disk' { Scan-Disk; $app.dsel = 0 }
        { $_ -in 'ram', 'procs' } { Load-Procs; $app.psel = 0; $app.ptop = 0; $app.marks = @{}; $app.sys = Get-Sys }
        'settings' { $app.ssel = 0 }
        'main' { $app.sys = Get-Sys }
        'appclean' { $app.items = @(); Load-Rules; Set-Items @(Group-Keep $app.rules 'Cat') }
        'tweaks' { $app.items = @(); Load-Tweaks; Set-Items @(Group-Keep $app.tweaks 'Cat') }
        'uninst' {
            $app.items = @(); Load-Apps
            Set-Items @(@('SUGGESTED: put there to advertise or sell', @($app.uapps | Where-Object Safety -eq 1)), @('YOUR APPS AND PROGRAMS', @($app.uapps | Where-Object Safety -eq 0)), @('PROTECTED: Windows needs these', @($app.uapps | Where-Object Safety -ge 2)))
        }
    }
}
function Invoke-Menu([string]$key) {
    $app.msg = ''
    switch ($key) {
        'B' { $app.back = 'main'; Start-Boost }
        'D' { Open-Screen 'disk' }
        'A' { Open-Screen 'appclean' }
        'R' { Open-Screen 'ram' }
        'P' { Open-Screen 'procs' }
        'T' { Open-Screen 'tweaks' }
        'U' { Open-Screen 'uninst' }
        'S' { Open-Screen 'settings' }
        'H' { Open-Screen 'help' }
        'Q' { $app.quit = $true }
    }
}
function Key-main([string]$k) {
    switch ($k) {
        'UP' { $app.sel = ($app.sel + $menu.Count - 1) % $menu.Count }
        'DOWN' { $app.sel = ($app.sel + 1) % $menu.Count }
        { $_ -in 'LEFT', 'RIGHT' } { $app.sel = ($app.sel + 5) % $menu.Count }   # the other column
        'ENTER' { Invoke-Menu $menu[$app.sel].Key }
        'F1' { Open-Screen 'help' }
        default { if ($menu.Key -contains $k) { Invoke-Menu $k } }
    }
}
function Key-help([string]$k) { Open-Screen 'main' }
function Key-result([string]$k) {
    if ($k -eq 'X' -and $app.res.Restart -contains 'explorer' -and -not $app.res.Dry) { Restart-Explorer; $app.res.Restart = @(); Set-Msg 'Explorer restarted.' 'ok'; return }
    if ($script:ExitAfter) { $app.quit = $true } else { Open-Screen $app.back }
}
function Key-appclean([string]$k) {
    if (Move-Sel $k) { return }
    $x = $app.items[$app.lsel]
    switch ($k) {
        'SPACE' {
            if (-not $x) { break }
            if (-not $x.Head -and -not $x.Ready) { Set-Msg "Cannot run now: $($x.Why)." 'warn'; break }
            $m = @(if ($x.Head) { $x.Members | Where-Object Ready } else { $x })
            $to = [bool]@($m | Where-Object { -not $_.On }).Count   # anything unticked: tick all; else clear all
            foreach ($r in $m) { $r.On = $to }
            $app.acDirty = $true
        }
        'A' { foreach ($r in $app.rules) { $r.On = Get-SafeTick $r }; $app.acDirty = $true; Set-Msg 'Safe set: only cache, temp and log cleaners are ticked.' }
        'N' { foreach ($r in $app.rules) { $r.On = $false }; $app.acDirty = $true }
        'S' { Scan-Rules @($app.rules | Where-Object { $_.On -and $_.Ready }); Set-Msg 'Scanned: sizes are what the ticked cleaners would delete now.' }
        'ENTER' {
            $sel = @(Get-RuleJobs)
            if ($sel) { Save-Ticks; Start-Run @{ Title = 'APP CLEAN'; Clean = $sel; Ask = $true; Skipped = (Get-Skipped $app.rules) } } else { Set-Msg 'Nothing to clean: tick something (or nothing was found).' 'warn' }
        }
        'ESC' { Save-Ticks; Open-Screen 'main' }
    }
}
function Key-tweaks([string]$k) {
    if (Move-Sel $k) { return }
    $x = $app.items[$app.lsel]
    switch ($k) {
        'SPACE' {
            if (-not $x) { break }
            if ($x.Head) {
                $m = @($x.Members | Where-Object { -not $_.Locked -and $_.State -eq 'off' })
                $to = [bool]@($m | Where-Object { -not $_.Mark }).Count
                foreach ($t in $m) { $t.Mark = if ($to) { 'apply' } else { $null } }
                Clear-Groups; break
            }
            if ($x.Locked) { Set-Msg 'Needs admin: right-click RetroBoost.cmd > Run as administrator.' 'warn'; break }
            if (-not $x.Mark -and $x.State -eq 'on' -and @($x.Vals | Where-Object { -not $_.Def }).Count) { Set-Msg 'Already on, and the catalogue records no Windows default to go back to.' 'warn'; break }
            $x.Mark = if ($x.Mark) { $null } elseif ($x.State -eq 'on') { 'undo' } else { 'apply' }
            if ($x.Mark -and $x.Group) { foreach ($t in $app.tweaks) { if ($t -ne $x -and $t.Group -eq $x.Group) { $t.Mark = $null } } }   # variants of one setting: only one may win
        }
        'A' { foreach ($t in $app.tweaks) { $t.Mark = if ($t.Rec -and $t.State -eq 'off' -and -not $t.Locked) { 'apply' } else { $null } }; Clear-Groups; Set-Msg 'Recommended settings ticked.' }
        'N' { foreach ($t in $app.tweaks) { $t.Mark = $null } }
        'ENTER' { $sel = @($app.tweaks | Where-Object Mark); if ($sel) { Start-Run @{ Title = 'TWEAKS'; Tweak = $sel; Ask = $true } } else { Set-Msg 'Nothing ticked.' 'warn' } }
        'ESC' { Open-Screen 'main' }
    }
}
function Key-uninst([string]$k) {
    if (Move-Sel $k) { return }
    $x = $app.items[$app.lsel]
    switch ($k) {
        'SPACE' {
            if (-not $x) { break }
            $m = @(@(if ($x.Head) { $x.Members } else { $x }) | Where-Object { $_.Safety -lt 2 })
            if (-not $m.Count) { Set-Msg 'Protected: Windows (or RetroBoost) needs this.' 'warn'; break }
            $to = [bool]@($m | Where-Object { -not $_.On }).Count
            foreach ($a in $m) { $a.On = $to }
        }
        'A' { foreach ($a in $app.uapps) { $a.On = $a.Safety -eq 1 }; Set-Msg 'Suggested apps ticked: read the list before you press ENTER.' }
        'N' { foreach ($a in $app.uapps) { $a.On = $false } }
        'ENTER' { $sel = @($app.uapps | Where-Object On); if ($sel) { Start-Run @{ Title = 'UNINSTALL'; Uninstall = $sel; Ask = $true } } else { Set-Msg 'Nothing ticked.' 'warn' } }
        'ESC' { Open-Screen 'main' }
    }
}
function Key-disk([string]$k) {
    $n = $app.cats.Count
    switch ($k) {
        'UP' { if ($n) { $app.dsel = ($app.dsel + $n - 1) % $n } }
        'DOWN' { if ($n) { $app.dsel = ($app.dsel + 1) % $n } }
        'SPACE' { $c = $app.cats[$app.dsel]; if ($c.Ready) { $c.On = -not $c.On } else { Set-Msg "Cannot run: $($c.Why)" 'warn' } }
        'A' { foreach ($c in $app.cats) { $def = $cats | Where-Object { $_.Id -eq $c.Id }; $c.On = $c.Ready -and $def.On } }
        'N' { foreach ($c in $app.cats) { $c.On = $false } }
        'W' { if (-not $script:Test) { Start-Process 'ms-settings:storagesense' }; Set-Msg 'Opened Settings > System > Storage > Temporary files.' }
        'ENTER' {
            $sel = @($app.cats | Where-Object { $_.On -and $_.Ready })
            if ($sel) { Start-Run @{ Title = 'DISK CLEAN'; Clean = $sel; Ask = $true; Skipped = (Get-Skipped $app.cats) } } else { Set-Msg 'Nothing ticked.' 'warn' }
        }
        'ESC' { Open-Screen 'main' }
    }
}
function Key-ram([string]$k) {
    switch ($k) {
        'T' { Start-Run @{ Title = 'RAM TRIM'; Ram = $true } }
        'ESC' { Open-Screen 'main' }
    }
}
function Stop-Selected([bool]$force) {
    $names = @($app.marks.Keys)
    if (-not $names) { $p = $app.plist[$app.psel]; if ($p -and -not $p.Prot) { $names = @($p.Name) } }
    if (-not $names) { Set-Msg 'Nothing to stop: protected programs cannot be stopped here.' 'warn'; return }
    Start-Run @{ Title = $(if ($force) { 'FORCE STOP' } else { 'STOP PROGRAMS' }); Kill = $names; Force = $force; Ask = $true }
}
function Key-procs([string]$k) {
    $n = $app.plist.Count
    switch ($k) {
        'UP' { if ($app.psel -gt 0) { $app.psel-- } }
        'DOWN' { if ($app.psel -lt $n - 1) { $app.psel++ } }
        'PGUP' { $app.psel = [Math]::Max(0, $app.psel - 14) }
        'PGDN' { $app.psel = [Math]::Max(0, [Math]::Min($n - 1, $app.psel + 14)) }
        'HOME' { $app.psel = 0 }
        'END' { $app.psel = [Math]::Max(0, $n - 1) }
        'SPACE' {
            $p = $app.plist[$app.psel]
            if ($p.Prot) { Set-Msg "$($p.Name) is protected." 'warn' } elseif ($app.marks.ContainsKey($p.Name)) { $app.marks.Remove($p.Name) } else { $app.marks[$p.Name] = $true }
        }
        'K' {
            $p = $app.plist[$app.psel]
            if ($p.Prot) { Set-Msg "$($p.Name) is protected and cannot go on the kill list." 'warn'; break }
            if ($cfg.killList -contains $p.Name) { $cfg.killList = @($cfg.killList | Where-Object { $_ -ine $p.Name }); Set-Msg "$($p.Name) removed from the kill list." }
            else { $cfg.killList = @($cfg.killList) + $p.Name; Set-Msg "$($p.Name) added: BOOST will close it." 'ok' }
            $script:Dirty = $true
        }
        'X' { Stop-Selected $false }
        'F' { Stop-Selected $true }
        'S' { $app.psort = if ($app.psort -eq 'mem') { 'name' } else { 'mem' }; Sort-Procs; $app.psel = 0 }
        'ESC' { Open-Screen 'main' }
    }
}
function Key-settings([string]$k) {
    $n = 6 + [Math]::Min(8, $cfg.killList.Count)
    switch ($k) {
        'UP' { $app.ssel = ($app.ssel + $n - 1) % $n }
        'DOWN' { $app.ssel = ($app.ssel + 1) % $n }
        { $_ -in 'ENTER', 'LEFT', 'RIGHT', 'SPACE' } {
            switch ($app.ssel) {
                0 { $names = 'blue', 'green', 'amber'; $cfg.theme = $names[([array]::IndexOf($names, $cfg.theme) + 1) % 3]; Set-Theme $cfg.theme; if (-not $script:Test) { [Console]::Write("$($script:Sgr[0])${CSI}2J") } }
                1 { $cfg.sound = -not $cfg.sound }
                2 { $cfg.confirm = -not $cfg.confirm }
                3 { $script:Dry = -not $script:Dry }
                4 { $cfg.boostApps = -not $cfg.boostApps; Set-Msg $(if ($cfg.boostApps) { 'BOOST now also runs your APP CLEAN ticks.' } else { 'BOOST is back to the safe built-in categories.' }) }
                5 {
                    $names = 'off', 'daily', 'weekly', 'logon'; $new = $names[([array]::IndexOf($names, $cfg.schedule) + 1) % 4]
                    $m = Set-Schedule $new
                    if ($m -like 'Could not*') { Set-Msg $m 'warn' } else { $cfg.schedule = $new; Set-Msg $m 'ok' }
                }
            }
            $script:Dirty = $true
        }
        'DEL' {
            if ($app.ssel -ge 6) { $gone = $cfg.killList[$app.ssel - 6]; $cfg.killList = @($cfg.killList | Where-Object { $_ -ne $gone }); $script:Dirty = $true; Set-Msg "$gone removed from the kill list."; $app.ssel = [Math]::Min($app.ssel, 5 + $cfg.killList.Count) }
        }
        'ESC' { Save-Cfg; Open-Screen 'main' }
    }
}

# ---------- plan, run, boost ----------
# a run is one hashtable: Title, Clean (disk categories and APP CLEAN rules), Kill (program names), Ram, Force,
# Tweak (settings with Mark apply/undo), Uninstall (apps), Ask (show the plan first), Skipped (what could not run, and why).
# Read the lists as $job['Key']: a missing key would otherwise find a Hashtable method of the same name.
function Get-Skipped($pool) { @($pool | Where-Object { $_.On -and -not $_.Ready -and $_.Why -notin 'nothing', 'sandbox' } | ForEach-Object { "$($_.Id): $($_.Why)" }) }
function Arr($x) { , @($x | Where-Object { $null -ne $_ }) }   # a list, never @($null)
function Show-Plan($job) {
    $sel = Arr $job['Clean']; $kill = Arr $job['Kill']; $tw = Arr $job['Tweak']; $rm = Arr $job['Uninstall']
    $ln = [System.Collections.Generic.List[object]]::new()
    if ($script:Dry) { $ln.Add(@('DRY-RUN is on: nothing will really change.', 'warn')) }
    if ($job['Force']) { $ln.Add(@('FORCE: programs are killed at once. Unsaved work in them is lost.', 'bad')) }
    if ($sel.Count) {
        $ln.Add(@(('DISK   clean {0} item(s), about {1}' -f $sel.Count, (Gb ($sel | Measure-Object Bytes -Sum).Sum)), 'hi'))
        foreach ($c in $sel | Select-Object -First 5) { $ln.Add(@(('      {0} {1,10}' -f (Fit $c.Name 41), (Sz $c.Bytes)), 'norm')) }
        if ($sel.Count -gt 5) { $ln.Add(@("      ... and $($sel.Count - 5) more", 'dim')) }
    }
    if ($kill.Count) {
        $ln.Add(@(('STOP   {0} program(s): {1}' -f $kill.Count, (($kill | Select-Object -First 6) -join ', ')), 'hi'))
        $ln.Add(@('      windowed apps are asked to close, so they can save', 'dim'))
    } elseif ($job['Title'] -eq 'BOOST') { $ln.Add(@('STOP   nothing: your kill list is empty (add programs on PROCESSES, key K)', 'dim')) }
    if ($job['Ram']) { $ln.Add(@('RAM    ask Windows to page out idle memory (temporary relief)', 'hi')) }
    if ($tw.Count) {
        $un = @($tw | Where-Object Mark -eq 'undo').Count
        $ln.Add(@(('SET    {0} setting(s) to the catalogue value, undo {1}' -f ($tw.Count - $un), $un), 'hi'))
        foreach ($t in $tw | Select-Object -First 6) { $ln.Add(@(('      {0} {1}' -f $(if ($t.Mark -eq 'undo') { 'undo ' } else { 'apply' }), $t.Name), 'norm')) }
        if ($tw.Count -gt 6) { $ln.Add(@("      ... and $($tw.Count - 6) more", 'dim')) }
        $ln.Add(@('      every value is read back; the log keeps what changed', 'dim'))
    }
    if ($rm.Count) {
        $ln.Add(@(('REMOVE {0} app(s)' -f $rm.Count), 'hi'))
        foreach ($a in $rm | Select-Object -First 6) { $ln.Add(@(('      {0}  ({1})' -f $a.Name, $a.Kind), 'norm')) }
        if ($rm.Count -gt 6) { $ln.Add(@("      ... and $($rm.Count - 6) more", 'dim')) }
        $ln.Add(@('      RetroBoost cannot undo this. Store apps come back', 'warn'))
        $ln.Add(@('      from the Microsoft Store; programs may open a window.', 'warn'))
    }
    $ln.Add(@('', 'norm')); $ln.Add(@('Windows, security tools and this terminal are never touched.', 'dim'))
    Dialog " $($job['Title']) - PLAN " $ln 'ENTER = GO        ESC = cancel'
    Show-Buf
    (Read-Key) -eq 'ENTER'
}
function Wait-Auto([string]$title) {
    if ($script:Test) { return $true }
    for ($i = 3; $i -ge 1; $i--) {
        Dialog " $title - ONE CLICK " @(@("Starting in $i ...", 'hi'), @('Cleans junk, trims RAM, closes your kill-list programs.', 'norm')) 'ESC = cancel'
        Show-Buf
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.ElapsedMilliseconds -lt 1000) { if ([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -eq 'Escape') { return $false }; Start-Sleep -Milliseconds 30 }
    }
    $true
}
function RunLine([string]$style, [string]$text) {
    $app.log.Add(@($style, $text)); if ($app.log.Count -gt 11) { $app.log.RemoveAt(0) }
    Draw-run; Show-Buf
}
function RunSet([string]$style, [string]$text) { $app.log[$app.log.Count - 1] = @($style, $text); Draw-run; Show-Buf }

function Start-Run($job) {
    $title = $job['Title']; $sel = Arr $job['Clean']; $kill = Arr $job['Kill']; $tw = Arr $job['Tweak']; $rm = Arr $job['Uninstall']; $ram = [bool]$job['Ram']; $force = [bool]$job['Force']
    if ($script:AutoYes) { $script:AutoYes = $false; if (-not (Wait-Auto $title)) { $script:ExitAfter = $false; Set-Msg 'Cancelled.'; return } }
    elseif ($job['Ask'] -and (($title -ne 'BOOST') -or $cfg.confirm) -and -not (Show-Plan $job)) { Set-Msg 'Cancelled.'; return }
    $before = Get-Sys
    $app.screen = 'run'; $app.title = $title; $app.pct = 0; $app.log = [System.Collections.Generic.List[object]]::new(); Set-Msg ''
    $total = [Math]::Max(1, $sel.Count + $kill.Count + [int]$ram + $tw.Count + $rm.Count); $done = 0
    $freed = 0L; $closed = [System.Collections.Generic.List[string]]::new(); $stuck = [System.Collections.Generic.List[string]]::new(); $trim = $null
    $twOk = 0; $twUndo = 0; $twFail = [System.Collections.Generic.List[string]]::new(); $restart = [System.Collections.Generic.List[string]]::new()
    $removed = [System.Collections.Generic.List[string]]::new(); $rmFail = [System.Collections.Generic.List[string]]::new()
    Write-Log "$title start"
    foreach ($c in $sel) {
        RunLine 'dim' ('[ .. ] {0}' -f $c.Name)
        $b = Invoke-Clean $c; $freed += $b; $done++; $app.pct = [int](100 * $done / $total)
        RunSet 'ok' ('[ OK ] {0} {1,10}' -f (Fit $c.Name 42), (Sz $b)); Write-Log "clean $($c.Id): $(Gb $b)"
    }
    foreach ($t in $tw) {
        $verb = if ($t.Mark -eq 'undo') { 'undo' } else { 'apply' }
        RunLine 'dim' ('[ .. ] {0} {1}' -f $verb, $t.Name)
        $ok = Invoke-Tweak $t; $done++; $app.pct = [int](100 * $done / $total)
        if ($ok) {
            if ($verb -eq 'undo') { $twUndo++ } else { $twOk++ }
            if ($t.Restart -and $restart -notcontains $t.Restart) { $restart.Add($t.Restart) }
            RunSet 'ok' ('[ OK ] {0} {1}' -f $verb, $t.Name)
        } else { $twFail.Add($t.Name); RunSet 'warn' ('[FAIL] {0} {1}{2}' -f $verb, $t.Name, $(if ($t.Admin -and -not $script:IsAdmin) { ' (needs admin)' })) }
        Write-Log "tweak ${verb}: $($t.Name): $(if ($ok) { 'ok' } else { 'FAILED' })"
    }
    if ($twOk + $twUndo) { Send-SettingChange }   # Explorer and open apps re-read theme and taskbar values
    foreach ($a in $rm) {
        RunLine 'dim' ('[ .. ] removing {0}{1}' -f $a.Name, $(if ($a.Kind -eq 'program' -and -not $Demo -and -not $script:Dry) { '  (finish it in its own window if one opens)' }))
        $ok = Remove-App $a; $done++; $app.pct = [int](100 * $done / $total)
        if ($ok) { $removed.Add($a.Name); RunSet 'ok' ('[ OK ] removed {0}' -f $a.Name) } else { $rmFail.Add($a.Name); RunSet 'warn' ('[FAIL] {0} is still installed' -f $a.Name) }
        Write-Log "uninstall $($a.Kind) $($a.Name) [$($a.Family)]: $(if ($ok) { 'removed' } else { 'still there' })"
    }
    foreach ($n in $kill) {
        RunLine 'dim' ('[ .. ] stopping {0}' -f $n)
        $r = Stop-App $n $force; $done++; $app.pct = [int](100 * $done / $total)
        if ($r.Left -gt 0) { $stuck.Add($n); RunSet 'warn' ('[WAIT] {0} still open ({1} process(es))' -f $n, $r.Left) }
        elseif ($r.Closed -gt 0) { $closed.Add($n); RunSet 'ok' ('[ OK ] {0} stopped ({1} process(es))' -f $n, $r.Closed) }
        else { RunSet 'dim' ('[SKIP] {0} is not running or is protected' -f $n) }
        Write-Log "stop ${n}: closed $($r.Closed), left $($r.Left)"
    }
    if ($ram) {
        RunLine 'dim' '[ .. ] trimming RAM'
        $trim = Invoke-RamTrim; $done++; $app.pct = [int](100 * $done / $total)
        RunSet 'ok' ('[ OK ] RAM trimmed ({0:+#,0;-#,0;0} MB available)' -f (($trim.After - $trim.Before) / 1MB)); Write-Log "ram trim: $(Mb $trim.Before) -> $(Mb $trim.After), $($trim.Count) processes"
    }
    $app.pct = 100; Draw-run; Show-Buf
    $after = Get-Sys
    $app.res = [pscustomobject]@{
        Dry = $script:Dry; Cleaned = [bool]$sel.Count; Freed = $freed; Trimmed = [bool]$ram; Closed = @($closed); Stuck = @($stuck); Skipped = (Arr $job['Skipped'])
        DiskBefore = $before.DiskFree; DiskAfter = $after.DiskFree; RamBefore = $before.RamFree; RamAfter = $after.RamFree   # whole run, so freed programs count too
        Tweaked = $twOk; Undone = $twUndo; TwFail = @($twFail); Restart = @($restart); Removed = @($removed); RmFail = @($rmFail)
    }
    Write-Log ("$title done: freed {0}" -f (Gb $freed))
    $app.screen = 'result'; Snd 'ok'
}
function Start-Boost {
    Scan-Disk
    $sel = @($app.cats | Where-Object { $_.On -and $_.Ready }); $skip = @($app.cats)
    if ($cfg.boostApps) { Load-Rules; $sel += @(Get-RuleJobs); $skip += @($app.rules) }   # SETTINGS > BOOST+APP CLEAN
    Start-Run @{ Title = 'BOOST'; Clean = $sel; Kill = @(Get-KillTargets); Ram = $true; Ask = $true; Skipped = (Get-Skipped $skip) }
}

# ---------- terminal ----------
function Enter-Term {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    if ([Console]::IsInputRedirected) { Write-Host 'RetroBoost needs an interactive console (it reads the keyboard).'; return $false }
    if ([Console]::WindowWidth -lt 80 -or [Console]::WindowHeight -lt 26) {
        Write-Host ('Window too small ({0}x{1}). RetroBoost needs at least 80x26: enlarge it and start again.' -f [Console]::WindowWidth, [Console]::WindowHeight)
        return $false
    }
    [Console]::TreatControlCAsInput = $true
    [Console]::Write("${CSI}?1049h${CSI}?25l$($script:Sgr[0])${CSI}2J")   # alternate screen, hidden cursor, themed background
    $true
}
function Leave-Term { [Console]::Write("${CSI}0m${CSI}?25h${CSI}?1049l"); [Console]::TreatControlCAsInput = $false }
function Show-Splash {
    $cpu = if ($Demo) { 'RETRO-CPU 8-core @ 3.20 GHz (demo)' } else { ((Get-CimInstance Win32_Processor | Select-Object -First 1).Name -replace '\s+', ' ').Trim() }
    $y = $app.sys; $totMb = [int]($y.RamTotal / 1MB)
    Clear-Buf
    $step = {
        param($row, $text, $style)
        Put $row 2 $text $style; Show-Buf
        if ([Console]::KeyAvailable) { [void][Console]::ReadKey($true); return $true }
        Start-Sleep -Milliseconds 110; $false
    }
    if (& $step 1 'RETROBOOST BIOS v2.0        (C) 1987-2026 RETRO SOFTWARE' $sty.hi) { return }
    if (& $step 3 ('CPU       : {0}' -f $cpu) $sty.norm) { return }
    for ($m = 0; $m -lt 10; $m++) { Put 4 2 ('RAM TEST  : {0,6} MB' -f [int]($totMb * ($m + 1) / 10)) $sty.norm; Show-Buf; Start-Sleep -Milliseconds 35 }
    Put 4 60 '[ OK ]' $sty.ok; Put 3 60 '[ OK ]' $sty.ok
    if (& $step 5 ('DISK C:   : {0} used, {1} free' -f (Gb ($y.DiskTotal - $y.DiskFree)), (Gb $y.DiskFree)) $sty.norm) { return }
    Put 5 60 '[ OK ]' $sty.ok
    if (& $step 6 ('KILL LIST : {0} program(s)' -f $cfg.killList.Count) $sty.norm) { return }
    Put 6 60 '[ OK ]' $sty.ok
    if (& $step 7 'SAFETY    : protected processes locked' $sty.norm) { return }
    Put 7 60 '[ OK ]' $sty.ok; Snd 'ok'
    if (& $step 9 'BOOTING RETROBOOST_' $sty.hi) { return }
    Start-Sleep -Milliseconds 250
}

# ---------- main ----------
try {
    if ($Auto) { Invoke-Auto; return }   # Task Scheduler: no screen, no keyboard
    Set-Theme $cfg.theme
    $app.sys = Get-Sys; $app.cpu = if ($script:Test -and -not $Demo) { 0 } else { Get-Cpu }
    if ($Screenshot) {
        $names = if ($Screenshot -eq 'all') { 'main', 'disk', 'appclean', 'ram', 'procs', 'tweaks', 'uninst', 'settings', 'help' } else { , $Screenshot }
        foreach ($n in $names) { Open-Screen $n; Redraw }
        return
    }
    if (-not $script:Test) {
        if (-not (Enter-Term)) { return }
        if (-not $script:AutoYes) { Show-Splash }
    }
    Redraw
    if ($Boost) { Start-Boost }
    while (-not $app.quit) {
        Redraw
        $k = Read-Key 2500
        if ($k -eq 'EOF') { break }
        if ($k -eq 'TICK') { if ($app.screen -eq 'main') { $app.sys = Get-Sys; $app.cpu = Get-Cpu }; continue }
        & "Key-$($app.screen)" $k
    }
}
finally {
    if (-not $script:Quiet) { Leave-Term }
    if ($Dump -and $script:Dumped.Count) { $script:Dumped | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Dump -Encoding utf8 }
    Save-Cfg
}
