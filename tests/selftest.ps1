#Requires -Version 7
# Self-test for RetroBoost. Builds a throwaway sandbox of fake caches plus a fake "unwanted" program, then checks that a
# dry run changes nothing and a real BOOST removes exactly what it should. Nothing outside the sandbox is touched.
#   pwsh -File tests/selftest.ps1
$app = Join-Path $PSScriptRoot '..\src\retroboost.ps1'
$tmp = [IO.Path]::GetTempPath()
$sb = Join-Path $tmp ('rb-selftest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$script:fail = 0
function Check([string]$what, [bool]$ok) { if ($ok) { "  PASS  $what" } else { "  FAIL  $what"; $script:fail++ } }
function New-Fake([string]$rel, [int]$ageDays = 0) {
    $p = Join-Path $sb $rel
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $p)
    [IO.File]::WriteAllBytes($p, [byte[]]::new(200KB))
    (Get-Item -LiteralPath $p).LastWriteTime = (Get-Date).AddDays(-$ageDays)
}
function Present([string]$rel) { Test-Path -LiteralPath (Join-Path $sb $rel) }
$dummy = $null
try {
    $junk = 'Local\npm-cache\a.bin', 'Local\uv\cache\a.bin', 'Local\foo-updater\setup.exe', 'Local\CrashDumps\d.dmp', 'Roaming\Code\CachedExtensionVSIXs\v.vsix', 'home\.bun\install\cache\c.bin'
    foreach ($f in $junk) { New-Fake $f }
    New-Fake 'Temp\old.tmp' 3; New-Fake 'Temp\new.tmp' 0; New-Fake 'Temp\claude\keep.tmp' 3   # old goes; recent and the claude folder stay
    New-Fake 'Local\D3DSCache\s.bin'                                                          # shader caches are unticked by default
    Copy-Item "$env:windir\System32\ping.exe" (Join-Path $sb 'rbtestproc.exe')
    $dummy = Start-Process (Join-Path $sb 'rbtestproc.exe') -ArgumentList '-n', '600', '127.0.0.1' -WindowStyle Hidden -PassThru
    $cfgDir = Join-Path $sb 'cfg'; $null = New-Item -ItemType Directory -Force -Path $cfgDir

    'dry run (kill list also names explorer, which must be refused)'
    '{"theme":"blue","sound":false,"confirm":true,"killList":["rbtestproc","explorer"]}' | Set-Content (Join-Path $cfgDir 'config.json')
    $out = & $app -Sandbox $sb -ConfigDir $cfgDir -DryRun -Boost -Yes -Keys enter *>&1 | Out-String
    $left = @($junk + 'Temp\old.tmp' | Where-Object { Present $_ })
    Check 'dry run leaves every file' ($left.Count -eq $junk.Count + 1)
    Check 'dry run leaves the program running' (-not $dummy.HasExited)
    Check 'dry run reports the program it would stop' ($out -match 'WOULD STOP\s+rbtestproc')
    Check 'explorer is protected and never offered' ($out -notmatch 'explorer')

    'real boost'
    '{"theme":"blue","sound":false,"confirm":true,"killList":["rbtestproc"]}' | Set-Content (Join-Path $cfgDir 'config.json')
    $null = & $app -Sandbox $sb -ConfigDir $cfgDir -Boost -Yes -Keys enter *>&1
    $left = @($junk | Where-Object { Present $_ })
    Check 'caches, updater, dumps and VSIX cache removed' ($left.Count -eq 0)
    Check 'old temp file removed' (-not (Present 'Temp\old.tmp'))
    Check 'recent temp file kept' (Present 'Temp\new.tmp')
    Check 'claude temp folder kept' (Present 'Temp\claude\keep.tmp')
    Check 'shader cache kept (unticked)' (Present 'Local\D3DSCache\s.bin')
    $dummy.Refresh(); Check 'kill-list program stopped' $dummy.HasExited
    Check 'log written' (Test-Path (Join-Path $cfgDir 'boost.log'))

    'demo mode'
    $demoCfg = Join-Path $sb 'demo-cfg'
    $out = & $app -Demo -Boost -Yes -Keys enter -ConfigDir $demoCfg *>&1 | Out-String
    Check 'demo BOOST shows invented programs and pretend gains' ($out -match 'STOPPED\s+chatapp' -and $out -match 'DISK FREE')
    Check 'demo mode writes no log and no settings' (-not (Test-Path (Join-Path $demoCfg 'boost.log')) -and -not (Test-Path (Join-Path $demoCfg 'config.json')))
    $out = & $app -Demo -Screenshot all -ConfigDir $demoCfg *>&1 | Out-String
    Check 'all six screens render without errors' (([regex]::Matches($out, '(?m)^--- frame')).Count -eq 6 -and $out -notmatch 'Exception|InvalidOperation')
}
finally {
    if ($dummy -and -not $dummy.HasExited) { $dummy.Kill() }
    if ($sb.StartsWith($tmp) -and (Test-Path -LiteralPath $sb)) { Remove-Item -LiteralPath $sb -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($script:fail) { "`n$($script:fail) check(s) FAILED"; exit 1 } else { "`nall checks passed" }
