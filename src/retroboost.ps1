#Requires -Version 7
<#
.SYNOPSIS
RETROBOOST - a retro text-mode PC tune-up: free disk space, trim RAM and stop unwanted programs in one click.

.DESCRIPTION
Start it, press ENTER on BOOST NOW, press ENTER again to confirm. BOOST cleans safe junk (temp files, package and
browser caches, installer downloads, crash dumps), trims RAM and closes the programs on YOUR kill list. The kill list
starts empty: add programs on the PROCESSES screen with K. Windows and security processes are protected and can
never be stopped from here. -DryRun shows everything and changes nothing. Every action is logged to
%LOCALAPPDATA%\RetroBoost\boost.log. Keys: arrows move, ENTER selects, SPACE ticks, ESC goes back, F1 is help.

.EXAMPLE
pwsh -File .\retroboost.ps1               # the app

.EXAMPLE
pwsh -File .\retroboost.ps1 -Boost -Yes   # one click: 3-second countdown (ESC cancels), then BOOST

.EXAMPLE
pwsh -File .\retroboost.ps1 -DryRun       # try everything, change nothing

.EXAMPLE
pwsh -File .\retroboost.ps1 -Demo         # a tour with invented data: nothing on your PC is read, changed or stopped
#>
[CmdletBinding()]
param(
    [switch]$Boost, [switch]$Yes, [switch]$DryRun, [switch]$Demo,
    [ValidateSet('blue', 'green', 'amber')][string]$Theme,
    [string]$ConfigDir = (Join-Path $env:LOCALAPPDATA 'RetroBoost'),
    # test hooks: a sandbox folder replaces the real cache locations; scripted keys; plain-text screens; frame export
    [string]$Sandbox, [string[]]$Keys, [string]$Screenshot, [string]$Dump
)
if ($Keys) { $Keys = $Keys -split '[,\s]+' | Where-Object { $_ } }   # pwsh -File hands "a,b" over as one string

$script:Dry = [bool]$DryRun
$script:Test = [bool]($Keys -or $Screenshot)
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

# ---------- settings and log ----------
$cfgFile = Join-Path $ConfigDir 'config.json'
$logFile = Join-Path $ConfigDir 'boost.log'
$cfg = [ordered]@{ theme = 'blue'; sound = $true; confirm = $true; killList = @() }
if (Test-Path -LiteralPath $cfgFile) {
    try { $j = Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json; foreach ($k in @($cfg.Keys)) { if ($null -ne $j.$k) { $cfg[$k] = $j.$k } } } catch { }
}
$cfg.killList = @($cfg.killList | ForEach-Object { "$_" } | Where-Object { $_ })
if ($Theme) { $cfg.theme = $Theme }
if ($Demo) { $cfg.killList = @('chatapp', 'gamelauncher', 'updater-agent'); $cfg.sound = $false; $logFile = '%LOCALAPPDATA%\RetroBoost\boost.log' }
function Save-Cfg { if ($script:Dirty -and -not $Demo) { try { $null = New-Item -ItemType Directory -Force -Path $ConfigDir; $cfg | ConvertTo-Json | Set-Content -LiteralPath $cfgFile } catch { } } }
function Write-Log([string]$m) { if ($Demo) { return }; try { $null = New-Item -ItemType Directory -Force -Path $ConfigDir; Add-Content -LiteralPath $logFile ('{0:yyyy-MM-dd HH:mm:ss} {1}{2}' -f (Get-Date), $(if ($script:Dry) { '[DRY] ' }), $m) } catch { } }

# ---------- helpers ----------
function Gb($b) { '{0:N2} GB' -f ($b / 1GB) }
function Mb($b) { '{0:N0} MB' -f ($b / 1MB) }
function Fit([string]$s, [int]$n) { if ($s.Length -gt $n) { $s.Substring(0, $n) } else { $s.PadRight($n) } }
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
        if (-not $script:Test) { Redraw }
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
    if (-not $script:Test) { Redraw }   # clear the "SCANNING" line before any dialog is drawn on top
}

function Invoke-Clean($c) {
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

# ponytail: working-set trim only; flushing the standby list needs admin and is left out
function Invoke-RamTrim {
    $before = (Get-Sys).RamFree; $n = 0
    if ($Demo) { $script:DemoRam += 640MB; return [pscustomobject]@{ Before = $before; After = (Get-Sys).RamFree; Count = 88 } }
    if (-not $script:Dry) {
        if (-not ('RB.Mem' -as [type])) { Add-Type -Namespace RB -Name Mem -MemberDefinition '[DllImport("psapi.dll")] public static extern bool EmptyWorkingSet(IntPtr hProcess);' }
        $filter = if ($Sandbox) { 'rbtest*' } else { '*' }
        foreach ($p in Get-Process -Name $filter -ErrorAction SilentlyContinue) { try { if ([RB.Mem]::EmptyWorkingSet($p.Handle)) { $n++ } } catch { } }
        Start-Sleep -Milliseconds 500
    }
    [pscustomobject]@{ Before = $before; After = (Get-Sys).RamFree; Count = $n }
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
    Put 0 0 (Fit '  RETROBOOST v1.0   ::   PC TUNE-UP UTILITY' $COLS) $sty.title
    if ($Demo) { Put 0 ($COLS - 8) ' DEMO ' $sty.warn } elseif ($script:Dry) { Put 0 ($COLS - 11) ' DRY-RUN ' $sty.warn }
    Put ($ROWS - 1) 0 (Fit "  $hint" $COLS) $sty.title
    if ($app.msg) { Put ($ROWS - 2) 2 (Fit $app.msg ($COLS - 4)) $sty[$app.msgStyle] }
}

# ---------- app state and screens ----------
$app = @{ screen = 'main'; back = 'main'; sel = 0; msg = ''; msgStyle = 'dim'; quit = $false; sys = $null; cpu = 0
    cats = @(); dsel = 0; procs = @(); plist = @(); psel = 0; ptop = 0; psort = 'mem'; marks = @{}; ssel = 0; log = $null; pct = 0; title = ''; res = $null }
$menu = @(
    @{ Key = 'B'; Name = 'BOOST NOW'; Desc = 'clean junk, trim RAM, close your kill-list apps' }
    @{ Key = 'D'; Name = 'DISK CLEAN'; Desc = 'pick what to delete, see how much it frees' }
    @{ Key = 'R'; Name = 'RAM TRIM'; Desc = 'free memory, see the biggest memory users' }
    @{ Key = 'P'; Name = 'PROCESSES'; Desc = 'stop programs now, build your kill list' }
    @{ Key = 'S'; Name = 'SETTINGS'; Desc = 'theme, sound, safety switches' }
    @{ Key = 'Q'; Name = 'QUIT'; Desc = 'back to Windows' }
)
function Redraw { & "Draw-$($app.screen)"; Show-Buf }

function Draw-main {
    Draw-Chrome '↑↓ move    ENTER select    B D R P S Q hotkeys    F1 help'
    Draw-Logo 2 19 'RETROBOOST'
    Put 8 0 (Center '░▒▓  FREE DISK  ·  TRIM RAM  ·  STOP PROCESSES  ▓▒░') $sty.dim
    Box 9 2 6 74 ' SYSTEM STATUS '
    $y = $app.sys; $dUsed = $y.DiskTotal - $y.DiskFree; $rUsed = $y.RamTotal - $y.RamFree
    Gauge 10 4 'DISK C:' (100 * $dUsed / $y.DiskTotal) ('{0:N1} of {1:N1} GB used' -f ($dUsed / 1GB), ($y.DiskTotal / 1GB))
    Gauge 11 4 'RAM' (100 * $rUsed / $y.RamTotal) ('{0:N1} of {1:N1} GB used' -f ($rUsed / 1GB), ($y.RamTotal / 1GB))
    Gauge 12 4 'CPU' $app.cpu ('{0}% busy' -f $app.cpu)
    Put 13 4 ('Kill list: {0}   ·   Free disk: {1}   ·   Free RAM: {2}' -f $cfg.killList.Count, (Gb $y.DiskFree), (Mb $y.RamFree)) $sty.dim
    Box 15 2 8 74 ' MAIN MENU '
    for ($i = 0; $i -lt $menu.Count; $i++) {
        $m = $menu[$i]; $row = 16 + $i
        $line = ' [{0}]  {1}  {2}' -f $m.Key, $m.Name.PadRight(11), $m.Desc
        if ($i -eq $app.sel) { Put $row 3 (Fit $line 72) $sty.sel }
        else {
            Put $row 3 $line $sty.norm
            Put $row 5 $m.Key $sty.hi
            Put $row 9 $m.Name.PadRight(11) $(if ($i -eq 0) { $sty.hi } else { $sty.norm })
            Put $row 22 $m.Desc $sty.dim
        }
    }
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
    )
    for ($i = 0; $i -lt 4; $i++) {
        $line = ' {0}  < {1} >  {2}' -f (Fit $opts[$i][0] 15), (Fit $opts[$i][1] 6), $opts[$i][2]
        $st = if ($i -eq $app.ssel) { $sty.sel } else { $sty.norm }
        Put (3 + $i) 3 (Fit $line 72) $st
    }
    Put 9 4 'KILL LIST: BOOST closes these programs (add them with K on PROCESSES)' $sty.hi
    if (-not $cfg.killList.Count) { Put 11 6 '(empty: nothing is stopped until you add programs)' $sty.dim }
    for ($i = 0; $i -lt [Math]::Min(8, $cfg.killList.Count); $i++) {
        $n = $cfg.killList[$i]; $idx = 4 + $i
        $line = '  {0}{1}' -f $n, $(if ($n.ToLower() -in $protectedNames) { '   (protected, never stopped)' })
        Put (11 + $i) 3 (Fit $line 72) $(if ($idx -eq $app.ssel) { $sty.sel } else { $sty.norm })
    }
    Put 20 4 $(if ($Demo) { 'Demo mode: nothing is written, deleted or stopped.' } else { "Log: $logFile" }) $sty.dim
}

function Draw-help {
    Draw-Chrome 'any key = back'
    Box 1 1 22 76 ' HELP '
    $t = @(   # leading commas keep each line an array of its own
        , @('BOOST NOW   one click: clean safe junk, trim RAM, close your kill list.', 'hi')
        , @('DISK CLEAN  tick categories yourself. Only junk that comes back by', 'norm')
        , @('            itself is listed: temp files older than a day, package and', 'norm')
        , @('            browser caches, installer downloads, crash dumps. The', 'norm')
        , @('            Recycle Bin and GPU caches start unticked.', 'norm')
        , @('RAM TRIM    asks Windows to page out idle memory. Relief is temporary;', 'norm')
        , @('            closing heavy programs is what frees RAM for good.', 'norm')
        , @('PROCESSES   K adds a program to the kill list, X stops it now, F', 'norm')
        , @('            forces it (unsaved work is lost). Programs with a window', 'norm')
        , @('            are asked to close first so they can offer to save.', 'norm')
        , @('', 'norm')
        , @('SAFETY      Windows, security tools, drivers and this terminal', 'hi')
        , @('            are protected (#). A plan screen comes before every', 'norm')
        , @('            action unless CONFIRM is off. DRY-RUN changes nothing.', 'norm')
        , @('            Every action is written to the log shown in SETTINGS.', 'norm')
        , @('', 'norm')
        , @('ONE CLICK   RetroBoost-OneClick.cmd: 3-second countdown, then BOOST.', 'hi')
        , @('            ESC during the countdown cancels.', 'norm')
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
    Draw-Chrome 'any key = continue'
    Box 3 4 18 70 $(if ($x.Dry) { ' RESULT  (dry-run: nothing changed) ' } else { ' RESULT ' })
    $dd = $x.DiskAfter - $x.DiskBefore; $rd = $x.RamAfter - $x.RamBefore
    Put 5 8 'DISK FREE' $sty.dim; Put 5 20 ('{0}  ->  {1}' -f (Gb $x.DiskBefore), (Gb $x.DiskAfter)) $sty.norm
    if (-not $x.Dry) { Put 5 52 ('{0}{1}' -f $(if ($dd -ge 0) { '+' } else { '-' }), (Gb ([Math]::Abs($dd)))) $sty.ok }
    Put 6 8 $(if ($x.Dry) { 'WOULD FREE' } else { 'CLEANED' }) $sty.dim; Put 6 20 ('{0} reported by the cleaners' -f (Gb $x.Freed)) $sty.hi
    if ($x.Trimmed -or $x.Closed.Count) {
        Put 8 8 'RAM FREE' $sty.dim; Put 8 20 ('{0}  ->  {1}' -f (Mb $x.RamBefore), (Mb $x.RamAfter)) $sty.norm
        if (-not $x.Dry) { Put 8 52 ('{0}{1}' -f $(if ($rd -ge 0) { '+' } else { '-' }), (Mb ([Math]::Abs($rd)))) $sty.ok }
        Put 9 20 'temporary: Windows refills it on demand' $sty.dim
    }
    if ($x.Closed.Count) { Put 11 8 $(if ($x.Dry) { 'WOULD STOP' } else { 'STOPPED' }) $sty.dim; Put 11 20 (Fit ($x.Closed -join ', ') 52) $sty.hi }
    if ($x.Stuck.Count) { Put 12 8 'STILL OPEN' $sty.dim; Put 12 20 (Fit (($x.Stuck -join ', ') + '  (a window is waiting for you)') 52) $sty.warn }
    if ($x.Skipped.Count) { Put 13 8 'SKIPPED' $sty.dim; Put 13 20 (Fit ($x.Skipped -join '; ') 52) $sty.warn }
    Put 15 8 'LOG' $sty.dim; Put 15 20 (Fit $logFile 52) $sty.dim
    Put 17 8 'Closing heavy programs frees RAM for real.' $sty.dim
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
    }
}
function Invoke-Menu([string]$key) {
    $app.msg = ''
    switch ($key) {
        'B' { $app.back = 'main'; Start-Boost }
        'D' { Open-Screen 'disk' }
        'R' { Open-Screen 'ram' }
        'P' { Open-Screen 'procs' }
        'S' { Open-Screen 'settings' }
        'Q' { $app.quit = $true }
    }
}
function Key-main([string]$k) {
    switch ($k) {
        'UP' { $app.sel = ($app.sel + $menu.Count - 1) % $menu.Count }
        'DOWN' { $app.sel = ($app.sel + 1) % $menu.Count }
        'ENTER' { Invoke-Menu $menu[$app.sel].Key }
        'F1' { Open-Screen 'help' }
        default { if ($menu.Key -contains $k) { Invoke-Menu $k } }
    }
}
function Key-help([string]$k) { Open-Screen 'main' }
function Key-result([string]$k) { if ($script:ExitAfter) { $app.quit = $true } else { Open-Screen $app.back } }
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
            if ($sel) { Start-Run $sel @() $false $false 'DISK CLEAN' $true } else { Set-Msg 'Nothing ticked.' 'warn' }
        }
        'ESC' { Open-Screen 'main' }
    }
}
function Key-ram([string]$k) {
    switch ($k) {
        'T' { Start-Run @() @() $true $false 'RAM TRIM' $false }
        'ESC' { Open-Screen 'main' }
    }
}
function Stop-Selected([bool]$force) {
    $names = @($app.marks.Keys)
    if (-not $names) { $p = $app.plist[$app.psel]; if ($p -and -not $p.Prot) { $names = @($p.Name) } }
    if (-not $names) { Set-Msg 'Nothing to stop: protected programs cannot be stopped here.' 'warn'; return }
    Start-Run @() $names $false $force $(if ($force) { 'FORCE STOP' } else { 'STOP PROGRAMS' }) $true
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
    $n = 4 + [Math]::Min(8, $cfg.killList.Count)
    switch ($k) {
        'UP' { $app.ssel = ($app.ssel + $n - 1) % $n }
        'DOWN' { $app.ssel = ($app.ssel + 1) % $n }
        { $_ -in 'ENTER', 'LEFT', 'RIGHT', 'SPACE' } {
            switch ($app.ssel) {
                0 { $names = 'blue', 'green', 'amber'; $cfg.theme = $names[([array]::IndexOf($names, $cfg.theme) + 1) % 3]; Set-Theme $cfg.theme; if (-not $script:Test) { [Console]::Write("$($script:Sgr[0])${CSI}2J") } }
                1 { $cfg.sound = -not $cfg.sound }
                2 { $cfg.confirm = -not $cfg.confirm }
                3 { $script:Dry = -not $script:Dry }
            }
            $script:Dirty = $true
        }
        'DEL' {
            if ($app.ssel -ge 4) { $gone = $cfg.killList[$app.ssel - 4]; $cfg.killList = @($cfg.killList | Where-Object { $_ -ne $gone }); $script:Dirty = $true; Set-Msg "$gone removed from the kill list."; $app.ssel = [Math]::Min($app.ssel, 3 + $cfg.killList.Count) }
        }
        'ESC' { Save-Cfg; Open-Screen 'main' }
    }
}

# ---------- plan, run, boost ----------
function Show-Plan($sel, $kill, [bool]$ram, [bool]$force, [string]$title) {
    $ln = [System.Collections.Generic.List[object]]::new()
    if ($script:Dry) { $ln.Add(@('DRY-RUN is on: nothing will really change.', 'warn')) }
    if ($force) { $ln.Add(@('FORCE: programs are killed at once. Unsaved work in them is lost.', 'bad')) }
    if ($sel.Count) {
        $ln.Add(@(('DISK   clean {0} item(s), about {1}' -f $sel.Count, (Gb ($sel | Measure-Object Bytes -Sum).Sum)), 'hi'))
        foreach ($c in $sel | Select-Object -First 5) { $ln.Add(@(('      {0} {1,10}' -f (Fit $c.Name 41), (Gb $c.Bytes)), 'norm')) }
        if ($sel.Count -gt 5) { $ln.Add(@("      ... and $($sel.Count - 5) more", 'dim')) }
    }
    if ($kill.Count) {
        $ln.Add(@(('STOP   {0} program(s): {1}' -f $kill.Count, (($kill | Select-Object -First 6) -join ', ')), 'hi'))
        $ln.Add(@('      windowed apps are asked to close, so they can save', 'dim'))
    } elseif ($title -eq 'BOOST') { $ln.Add(@('STOP   nothing: your kill list is empty (add programs on PROCESSES, key K)', 'dim')) }
    if ($ram) { $ln.Add(@('RAM    ask Windows to page out idle memory (temporary relief)', 'hi')) }
    $ln.Add(@('', 'norm')); $ln.Add(@('Windows, security tools and this terminal are never touched.', 'dim'))
    Dialog " $title - PLAN " $ln 'ENTER = GO        ESC = cancel'
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

function Start-Run($sel, $kill, [bool]$ram, [bool]$force, [string]$title, [bool]$ask) {
    $sel = @($sel); $kill = @($kill)
    if ($script:AutoYes) { $script:AutoYes = $false; if (-not (Wait-Auto $title)) { $script:ExitAfter = $false; Set-Msg 'Cancelled.'; return } }
    elseif ($ask -and (($title -ne 'BOOST') -or $cfg.confirm) -and -not (Show-Plan $sel $kill $ram $force $title)) { Set-Msg 'Cancelled.'; return }
    $before = Get-Sys
    $app.screen = 'run'; $app.title = $title; $app.pct = 0; $app.log = [System.Collections.Generic.List[object]]::new()
    $total = [Math]::Max(1, $sel.Count + $kill.Count + [int]$ram); $done = 0
    $freed = 0L; $closed = [System.Collections.Generic.List[string]]::new(); $stuck = [System.Collections.Generic.List[string]]::new(); $trim = $null
    $skipped = @($app.cats | Where-Object { $_.On -and -not $_.Ready -and $_.Why -notin 'nothing', 'sandbox' } | ForEach-Object { "$($_.Id): $($_.Why)" })
    Write-Log "$title start"
    foreach ($c in $sel) {
        RunLine 'dim' ('[ .. ] {0}' -f $c.Name)
        $b = Invoke-Clean $c; $freed += $b; $done++; $app.pct = [int](100 * $done / $total)
        RunSet 'ok' ('[ OK ] {0} {1,10}' -f (Fit $c.Name 42), (Gb $b)); Write-Log "clean $($c.Id): $(Gb $b)"
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
        Dry = $script:Dry; Freed = $freed; Trimmed = [bool]$ram; Closed = @($closed); Stuck = @($stuck); Skipped = $skipped
        DiskBefore = $before.DiskFree; DiskAfter = $after.DiskFree; RamBefore = $before.RamFree; RamAfter = $after.RamFree   # whole run, so freed programs count too
    }
    Write-Log ("$title done: freed {0}" -f (Gb $freed))
    $app.screen = 'result'; Snd 'ok'
}
function Start-Boost {
    Scan-Disk
    Start-Run @($app.cats | Where-Object { $_.On -and $_.Ready }) @(Get-KillTargets) $true $false 'BOOST' $true
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
    if (& $step 1 'RETROBOOST BIOS v1.0        (C) 1987-2026 RETRO SOFTWARE' $sty.hi) { return }
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
    Set-Theme $cfg.theme
    $app.sys = Get-Sys; $app.cpu = if ($script:Test -and -not $Demo) { 0 } else { Get-Cpu }
    if ($Screenshot) {
        $names = if ($Screenshot -eq 'all') { 'main', 'disk', 'ram', 'procs', 'settings', 'help' } else { , $Screenshot }
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
    if (-not $script:Test) { Leave-Term }
    if ($Dump -and $script:Dumped.Count) { $script:Dumped | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Dump -Encoding utf8 }
    Save-Cfg
}
