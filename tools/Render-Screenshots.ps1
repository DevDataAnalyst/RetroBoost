#Requires -Version 7
<#
.SYNOPSIS
Renders RetroBoost screens to PNG files straight from the app's own screen buffer, using the built-in -Demo data.

.DESCRIPTION
No terminal and no screenshot of a real PC is involved: the app runs in -Demo mode with -Dump, and this script paints
each dumped frame (characters plus colours) onto a bitmap. Windows only (System.Drawing). Re-run it after changing the UI
and commit the new PNGs. For real terminal captures, see docs/screenshots/README.md.

.EXAMPLE
pwsh -File tools/Render-Screenshots.ps1
#>
param([string]$OutDir = (Join-Path $PSScriptRoot '..\docs\screenshots'), [int]$Scale = 2)
Add-Type -AssemblyName System.Drawing
$app = Join-Path $PSScriptRoot '..\src\retroboost.ps1'
$null = New-Item -ItemType Directory -Force -Path $OutDir
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('rb-shots-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $tmp

# xterm 256-colour index -> colour (RetroBoost only uses the 6x6x6 colour cube and the grey ramp)
function Get-Rgb([int]$n) {
    if ($n -ge 232) { $v = 8 + 10 * ($n - 232); return [Drawing.Color]::FromArgb($v, $v, $v) }
    $n -= 16; $lv = 0, 95, 135, 175, 215, 255
    [Drawing.Color]::FromArgb($lv[[int][Math]::Floor($n / 36)], $lv[[int]([Math]::Floor($n / 6) % 6)], $lv[$n % 6])
}
function Mix($fg, $bg, [double]$a) { [Drawing.Color]::FromArgb([int]($bg.R + ($fg.R - $bg.R) * $a), [int]($bg.G + ($fg.G - $bg.G) * $a), [int]($bg.B + ($fg.B - $bg.B) * $a)) }

function Save-Frame($f, [string]$path) {
    $cw = 8 * $Scale; $ch = 17 * $Scale; $pad = 10 * $Scale; $cols = 78; $rows = 25
    $t = [Math]::Max(1, $Scale); $gap = 2 * $Scale   # line thickness; half the gap between the two lines of a double border
    $bmp = [Drawing.Bitmap]::new($cols * $cw + 2 * $pad, $rows * $ch + 2 * $pad)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $fgc = @(); $bgc = @(); $fgB = @(); $bgB = @(); $b25 = @(); $b50 = @(); $b75 = @(); $bold = @()
    foreach ($p in $f.palette) {
        $fg = Get-Rgb $p.fg; $bg = Get-Rgb $p.bg
        $fgB += [Drawing.SolidBrush]::new($fg); $bgB += [Drawing.SolidBrush]::new($bg); $bold += [bool]$p.bold; $bgc += $bg.ToArgb()
        $b25 += [Drawing.SolidBrush]::new((Mix $fg $bg 0.25)); $b50 += [Drawing.SolidBrush]::new((Mix $fg $bg 0.5)); $b75 += [Drawing.SolidBrush]::new((Mix $fg $bg 0.75))
    }
    $g.Clear((Get-Rgb $f.palette[0].bg))
    $reg = [Drawing.Font]::new('Consolas', 14 * $Scale, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
    $bld = [Drawing.Font]::new('Consolas', 14 * $Scale, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
    $fmt = [Drawing.StringFormat]::GenericTypographic
    $yoff = ($ch - $reg.Height) / 2
    for ($r = 0; $r -lt $rows; $r++) {
        for ($x = 0; $x -lt $cols; $x++) {
            $s = [Convert]::ToInt32([string]$f.styles[$r][$x], 16); $c = [string]$f.rows[$r][$x]
            $px = $pad + $x * $cw; $py = $pad + $r * $ch; $cx = $px + [int]($cw / 2); $cy = $py + [int]($ch / 2)
            if ($bgc[$s] -ne $bgc[0]) { $g.FillRectangle($bgB[$s], $px, $py, $cw, $ch) }
            $br = $fgB[$s]
            $h = { param($y, $x0, $x1) $g.FillRectangle($br, $x0, $y - [int]($t / 2), $x1 - $x0, $t) }     # horizontal stroke
            $v = { param($xx, $y0, $y1) $g.FillRectangle($br, $xx - [int]($t / 2), $y0, $t, $y1 - $y0) }   # vertical stroke
            switch ($c) {
                ' ' { }
                '█' { $g.FillRectangle($br, $px, $py, $cw, $ch) }
                '▓' { $g.FillRectangle($b75[$s], $px, $py, $cw, $ch) }
                '▒' { $g.FillRectangle($b50[$s], $px, $py, $cw, $ch) }
                '░' { $g.FillRectangle($b25[$s], $px, $py, $cw, $ch) }
                '─' { & $h $cy $px ($px + $cw) }
                '═' { & $h ($cy - $gap) $px ($px + $cw); & $h ($cy + $gap) $px ($px + $cw) }
                '║' { & $v ($cx - $gap) $py ($py + $ch); & $v ($cx + $gap) $py ($py + $ch) }
                '╔' { & $v ($cx - $gap) ($cy - $gap) ($py + $ch); & $v ($cx + $gap) ($cy + $gap) ($py + $ch); & $h ($cy - $gap) ($cx - $gap) ($px + $cw); & $h ($cy + $gap) ($cx + $gap) ($px + $cw) }
                '╗' { & $v ($cx + $gap) ($cy - $gap) ($py + $ch); & $v ($cx - $gap) ($cy + $gap) ($py + $ch); & $h ($cy - $gap) $px ($cx + $gap); & $h ($cy + $gap) $px ($cx - $gap) }
                '╚' { & $v ($cx - $gap) $py ($cy + $gap); & $v ($cx + $gap) $py ($cy - $gap); & $h ($cy + $gap) ($cx - $gap) ($px + $cw); & $h ($cy - $gap) ($cx + $gap) ($px + $cw) }
                '╝' { & $v ($cx + $gap) $py ($cy + $gap); & $v ($cx - $gap) $py ($cy - $gap); & $h ($cy + $gap) $px ($cx + $gap); & $h ($cy - $gap) $px ($cx - $gap) }
                default { $g.DrawString($c, $(if ($bold[$s]) { $bld } else { $reg }), $br, [single]$px, [single]($py + $yoff), $fmt) }
            }
        }
    }
    $bmp.Save($path, [Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

# file name, app arguments, which dumped frame to paint (a screen name, or text the frame must contain; first/last match)
$shots = @(
    @{ File = 'main'; Args = '-Screenshot', 'main'; Screen = 'main'; Which = 'last' }
    @{ File = 'disk'; Args = '-Screenshot', 'disk'; Screen = 'disk'; Which = 'last' }
    @{ File = 'ram'; Args = '-Screenshot', 'ram'; Screen = 'ram'; Which = 'last' }
    @{ File = 'processes'; Args = '-Screenshot', 'procs'; Screen = 'procs'; Which = 'last' }
    @{ File = 'settings'; Args = '-Screenshot', 'settings'; Screen = 'settings'; Which = 'last' }
    @{ File = 'help'; Args = '-Screenshot', 'help'; Screen = 'help'; Which = 'last' }
    @{ File = 'plan'; Args = '-Keys', 'b'; Match = 'BOOST - PLAN' }
    @{ File = 'running'; Args = '-Keys', 'b,enter'; Screen = 'run'; Which = 'last' }
    @{ File = 'result'; Args = '-Keys', 'b,enter'; Screen = 'result'; Which = 'last' }
    @{ File = 'theme-green'; Args = '-Screenshot', 'main', '-Theme', 'green'; Screen = 'main'; Which = 'last' }
    @{ File = 'theme-amber'; Args = '-Screenshot', 'main', '-Theme', 'amber'; Screen = 'main'; Which = 'last' }
)
try {
    foreach ($s in $shots) {
        $json = Join-Path $tmp "$($s.File).json"
        & pwsh -NoProfile -File $app -Demo -ConfigDir $tmp -Dump $json @($s.Args) *> $null
        $frames = @(Get-Content -LiteralPath $json -Raw -Encoding utf8 | ConvertFrom-Json)
        $m = if ($s.Match) { @($frames | Where-Object { ($_.rows -join "`n") -match $s.Match }) } else { @($frames | Where-Object { $_.screen -eq $s.Screen }) }
        $pick = if ($s.Which -eq 'first') { $m[0] } else { $m[-1] }
        $out = Join-Path $OutDir "$($s.File).png"
        Save-Frame $pick $out
        '{0,-12} {1,6:N0} KB  (frame {2}/{3})' -f "$($s.File).png", ((Get-Item $out).Length / 1KB), ([array]::IndexOf($frames, $pick) + 1), $frames.Count
    }
}
finally { if ($tmp.StartsWith([IO.Path]::GetTempPath()) -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } }
