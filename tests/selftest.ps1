#Requires -Version 7
# Self-test for RetroBoost. Builds a throwaway sandbox of fake caches, a fake "unwanted" program, a fake winapp2 rule set,
# a fake tweak catalogue and a throwaway registry key (HKCU\Software\RetroBoostSelfTest), then checks that a dry run
# changes nothing and that the real runs remove, write and undo exactly what they should. Nothing else is touched.
#   pwsh -File tests/selftest.ps1
$app = Join-Path $PSScriptRoot '..\src\retroboost.ps1'
$tmp = [IO.Path]::GetTempPath()
$sb = Join-Path $tmp ('rb-selftest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$reg = 'HKCU:\Software\RetroBoostSelfTest'
$uk = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\rbtest-app'
$script:fail = 0
function Check([string]$what, [bool]$ok) { if ($ok) { "  PASS  $what" } else { "  FAIL  $what"; $script:fail++ } }
function New-Fake([string]$rel, [int]$ageDays = 0) {
    $p = Join-Path $sb $rel
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $p)
    [IO.File]::WriteAllBytes($p, [byte[]]::new(200KB))
    (Get-Item -LiteralPath $p).LastWriteTime = (Get-Date).AddDays(-$ageDays)
}
function Present([string]$rel) { Test-Path -LiteralPath (Join-Path $sb $rel) }
function Start-Dummy { Start-Process (Join-Path $sb 'rbtestproc.exe') -ArgumentList '-n', '600', '127.0.0.1' -WindowStyle Hidden -PassThru }
function Get-Val([string]$name) { (Get-ItemProperty -LiteralPath "$reg\Tweak" -Name $name -ErrorAction SilentlyContinue).$name }
$dummy = $null; $dummy2 = $null
try {
    $junk = 'Local\npm-cache\a.bin', 'Local\uv\cache\a.bin', 'Local\foo-updater\setup.exe', 'Local\CrashDumps\d.dmp', 'Roaming\Code\CachedExtensionVSIXs\v.vsix', 'home\.bun\install\cache\c.bin'
    foreach ($f in $junk) { New-Fake $f }
    New-Fake 'Temp\old.tmp' 3; New-Fake 'Temp\new.tmp' 0; New-Fake 'Temp\claude\keep.tmp' 3   # old goes; recent and the claude folder stay
    New-Fake 'Local\D3DSCache\s.bin'                                                          # shader caches are unticked by default
    Copy-Item "$env:windir\System32\ping.exe" (Join-Path $sb 'rbtestproc.exe')
    $dummy = Start-Dummy
    $cfgDir = Join-Path $sb 'cfg'; $null = New-Item -ItemType Directory -Force -Path $cfgDir

    # APP CLEAN fixtures: a winapp2 rule set of our own, files that must go and files that must stay
    $appFiles = 'Local\RBTestApp\Cache\a.bin', 'Local\RBTestApp\Cache\sub\b.bin', 'Local\RBTestApp\Logs\x.log'
    $appKeep = 'Local\RBTestApp\Cache\keep.bin', 'Local\RBTestApp\Logs\keep.txt', 'home\Documents\note.txt', 'Local\RBTestApp\History\h.dat', 'Windows\Logs\cbs.log'
    foreach ($f in $appFiles + $appKeep) { New-Fake $f 3 }
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $sb 'data')
    @'
[RB Test Cache *]
LangSecRef=3021
DetectFile=%LocalAppData%\RBTestApp
FileKey1=%LocalAppData%\RBTestApp\Cache|*.*|RECURSE
FileKey2=%LocalAppData%\RBTestApp\Logs|*.log
FileKey3=%Documents%|*.txt
FileKey4=%WinDir%\Logs|*.log
ExcludeKey1=FILE|%LocalAppData%\RBTestApp\Cache\|keep.bin
RegKey1=HKCU\Software\RetroBoostSelfTest\MRU

[RB Test History *]
LangSecRef=3021
DetectFile=%LocalAppData%\RBTestApp
FileKey1=%LocalAppData%\RBTestApp\History|*.*

[RB Test Missing App *]
LangSecRef=3021
DetectFile=%LocalAppData%\RBMissingApp
FileKey1=%LocalAppData%\RBTestApp|*.*|RECURSE
'@ | Set-Content (Join-Path $sb 'data\Winapp2.ini')
    $null = New-Item -Path "$reg\MRU" -Force; New-ItemProperty -Path "$reg\MRU" -Name a -Value 'x' -Force | Out-Null

    'dry run (kill list also names explorer, which must be refused; APP CLEAN is part of BOOST)'
    '{"theme":"blue","sound":false,"confirm":true,"killList":["rbtestproc","explorer"],"boostApps":true}' | Set-Content (Join-Path $cfgDir 'config.json')
    $out = & $app -Sandbox $sb -ConfigDir $cfgDir -DryRun -Boost -Yes -Keys enter *>&1 | Out-String
    $left = @($junk + 'Temp\old.tmp' + $appFiles | Where-Object { Present $_ })
    Check 'dry run leaves every file' ($left.Count -eq $junk.Count + 1 + $appFiles.Count)
    Check 'dry run leaves the registry alone' (Test-Path "$reg\MRU")
    Check 'dry run leaves the program running' (-not $dummy.HasExited)
    Check 'dry run reports the program it would stop' ($out -match 'WOULD STOP\s+rbtestproc')
    Check 'explorer is protected and never offered' ($out -notmatch 'explorer')

    'real boost'
    '{"theme":"blue","sound":false,"confirm":true,"killList":["rbtestproc"],"boostApps":true}' | Set-Content (Join-Path $cfgDir 'config.json')
    New-Fake 'Local\RBTestApp\Cache\inuse.bin' 3
    $lock = [IO.File]::Open((Join-Path $sb 'Local\RBTestApp\Cache\inuse.bin'), 'Open', 'Read', 'Read')   # open without share-delete, like a running app
    try { $out = & $app -Sandbox $sb -ConfigDir $cfgDir -Boost -Yes -Keys enter *>&1 | Out-String } finally { $lock.Dispose() }
    $left = @($junk | Where-Object { Present $_ })
    Check 'caches, updater, dumps and VSIX cache removed' ($left.Count -eq 0)
    Check 'old temp file removed' (-not (Present 'Temp\old.tmp'))
    Check 'recent temp file kept' (Present 'Temp\new.tmp')
    Check 'claude temp folder kept' (Present 'Temp\claude\keep.tmp')
    Check 'shader cache kept (unticked)' (Present 'Local\D3DSCache\s.bin')
    $dummy.Refresh(); Check 'kill-list program stopped' $dummy.HasExited
    Check 'log written' (Test-Path (Join-Path $cfgDir 'boost.log'))

    'app clean (winapp2 rules, run by BOOST because BOOST+APP CLEAN is on)'
    Check 'rule files removed, sub-folders too (RECURSE)' (-not @($appFiles | Where-Object { Present $_ }).Count)
    Check 'ExcludeKey file kept' (Present 'Local\RBTestApp\Cache\keep.bin')
    Check 'a file in use is skipped, not fought' (Present 'Local\RBTestApp\Cache\inuse.bin')
    Check 'file pattern respected (*.log only)' (Present 'Local\RBTestApp\Logs\keep.txt')
    Check 'Documents never touched, whatever a rule says' (Present 'home\Documents\note.txt')
    Check 'the Windows folder never touched, whatever a rule says' (Present 'Windows\Logs\cbs.log')
    Check 'a rule that is not cache/temp/log starts unticked' (Present 'Local\RBTestApp\History\h.dat')
    Check 'RegKey removed' (-not (Test-Path "$reg\MRU"))

    'tweaks (a one-setting catalogue writing to the throwaway key)'
    @'
[RB Test Tweak]
Category=Privacy
Description=Self-test setting.
Path=HKCU\Software\RetroBoostSelfTest\Tweak
ValueName=Flag
ValueType=DWORD
RecommendedValue=0
DefaultValue=1
DefaultSelected=true
ValueName2=Mode
ValueType2=String
RecommendedValue2=off
DefaultValue2=<deletevalue>
'@ | Set-Content (Join-Path $sb 'data\WinRules.ini')
    $null = New-Item -Path "$reg\Tweak" -Force; New-ItemProperty -Path "$reg\Tweak" -Name Flag -Value 1 -PropertyType DWord -Force | Out-Null
    $null = & $app -Sandbox $sb -ConfigDir $cfgDir -DryRun -Keys t, a, enter, enter *>&1
    Check 'dry run writes no setting' ((Get-Val Flag) -eq 1 -and $null -eq (Get-Val Mode))
    $out = & $app -Sandbox $sb -ConfigDir $cfgDir -Keys t, a, enter, enter *>&1 | Out-String
    Check 'A + ENTER applies every value of the setting' ((Get-Val Flag) -eq 0 -and (Get-Val Mode) -eq 'off' -and $out -match '1 applied, 0 undone')
    $out = & $app -Sandbox $sb -ConfigDir $cfgDir -Keys t, space, enter, enter *>&1 | Out-String
    Check 'SPACE on an applied setting undoes it (default back, extra value deleted)' ((Get-Val Flag) -eq 1 -and $null -eq (Get-Val Mode) -and $out -match '0 applied, 1 undone')

    'uninstall (a throwaway program entry in HKCU whose silent "uninstaller" deletes its own entry; -Sandbox lists only rbtest* programs)'
    $null = New-Item -Path $uk -Force
    New-ItemProperty -Path $uk -Name DisplayName -Value 'rbtest app' -Force | Out-Null
    New-ItemProperty -Path $uk -Name UninstallString -Value 'cmd.exe /c exit 0' -Force | Out-Null   # the window step: changes nothing, so only the silent step can pass
    New-ItemProperty -Path $uk -Name QuietUninstallString -Value ('reg.exe delete "{0}" /f' -f $uk.Replace('HKCU:', 'HKCU')) -Force | Out-Null
    $null = & $app -Sandbox $sb -ConfigDir $cfgDir -DryRun -Keys u, space, enter, enter *>&1
    Check 'dry run uninstalls nothing' (Test-Path $uk)
    $out = & $app -Sandbox $sb -ConfigDir $cfgDir -Keys u, space, enter, enter *>&1 | Out-String
    Check 'the silent uninstaller ran and Windows no longer lists the program' (-not (Test-Path $uk) -and $out -match 'REMOVED\s+1: rbtest app')

    'auto (the windowless Task Scheduler run)'
    New-Fake 'Local\npm-cache\again.bin'; $dummy2 = Start-Dummy
    $out = & $app -Sandbox $sb -ConfigDir $cfgDir -Auto *>&1 | Out-String
    Check '-Auto cleans and reports' (-not (Present 'Local\npm-cache\again.bin') -and $out -match 'RetroBoost AUTO')
    Check '-Auto never stops programs' (-not $dummy2.HasExited)
    Check '-Auto is logged' ((Get-Content (Join-Path $cfgDir 'boost.log') -Raw) -match 'AUTO done')

    'demo mode'
    $demoCfg = Join-Path $sb 'demo-cfg'
    $out = & $app -Demo -Boost -Yes -Keys enter -ConfigDir $demoCfg *>&1 | Out-String
    Check 'demo BOOST shows invented programs and pretend gains' ($out -match 'STOPPED\s+chatapp' -and $out -match 'DISK FREE')
    $out = & $app -Demo -Keys u, a, enter, enter -ConfigDir $demoCfg *>&1 | Out-String
    Check 'demo UNINSTALL removes the suggested apps' ($out -match 'REMOVED\s+4: Candy Cascade Saga')
    $out = & $app -Demo -Keys u, end, space -ConfigDir $demoCfg *>&1 | Out-String
    Check 'a protected app cannot be ticked' ($out -match 'Protected: Windows')
    Check 'demo mode writes no log and no settings' (-not (Test-Path (Join-Path $demoCfg 'boost.log')) -and -not (Test-Path (Join-Path $demoCfg 'config.json')))
    $out = & $app -Demo -Screenshot all -ConfigDir $demoCfg *>&1 | Out-String
    Check 'all nine screens render without errors' (([regex]::Matches($out, '(?m)^--- frame')).Count -eq 9 -and $out -notmatch 'Exception|InvalidOperation')
}
finally {
    foreach ($d in $dummy, $dummy2) { if ($d -and -not $d.HasExited) { $d.Kill() } }
    foreach ($k in $reg, $uk) { if (Test-Path $k) { Remove-Item -LiteralPath $k -Recurse -Force -ErrorAction SilentlyContinue } }
    if ($sb.StartsWith($tmp) -and (Test-Path -LiteralPath $sb)) { Remove-Item -LiteralPath $sb -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($script:fail) { "`n$($script:fail) check(s) FAILED"; exit 1 } else { "`nall checks passed" }
