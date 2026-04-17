$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

function New-Color([string]$hex, [int]$a = 255) {
  $hex = $hex.TrimStart('#')
  $r = [Convert]::ToInt32($hex.Substring(0,2),16)
  $g = [Convert]::ToInt32($hex.Substring(2,2),16)
  $b = [Convert]::ToInt32($hex.Substring(4,2),16)
  return [System.Drawing.Color]::FromArgb($a,$r,$g,$b)
}

function New-Bitmap([int]$w,[int]$h,[bool]$transparent=$true) {
  $bmp = New-Object System.Drawing.Bitmap -ArgumentList $w,$h,([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  if ($transparent) { $bmp.MakeTransparent() }
  return $bmp
}

function Save-Png($bmp,[string]$path) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

function With-Graphics($bmp, [ScriptBlock]$block) {
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  & $block $g
  $g.Dispose()
}

function New-RoundedRectPath([float]$x,[float]$y,[float]$w,[float]$h,[float]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $p.AddArc($x, $y, $d, $d, 180, 90) | Out-Null
  $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90) | Out-Null
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90) | Out-Null
  $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90) | Out-Null
  $p.CloseFigure() | Out-Null
  return $p
}

# Palette (soft / cozy)
$grassA = New-Color "#7db86a"
$grassB = New-Color "#8dca78"
$grassC = New-Color "#6fb15f"
$wood1  = New-Color "#c79b6a"
$wood2  = New-Color "#d6ad7a"
$wood3  = New-Color "#b87a4f"
$wood4  = New-Color "#a36a44"
$roofR  = New-Color "#c46a6a"
$roofR2 = New-Color "#b56c5e"
$blue   = New-Color "#8cc3d8"
$gold1  = New-Color "#ffd98e"
$gold2  = New-Color "#f0c76f"
$panel  = New-Color "#f2ead6"
$border = New-Color "#d9caa5"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")

Write-Host "Generating assets into $root\assets ..."

## --- Tiles (32x32) ---
function Make-GrassTile([int]$variant) {
  $bmp = New-Bitmap 32 32 $false
  With-Graphics $bmp {
    param($g)
    $g.Clear($grassA)
    $b1 = New-Object System.Drawing.SolidBrush $grassB
    $b2 = New-Object System.Drawing.SolidBrush $grassC
    $p1 = New-Object System.Drawing.Pen -ArgumentList $grassC, 2
    $p1.Color = [System.Drawing.Color]::FromArgb(120, $p1.Color)

    if ($variant -eq 0) {
      $g.FillEllipse($b1, 4, 4, 12, 12)
      $g.FillEllipse($b2, 14, 7, 14, 14)
      $g.FillEllipse($b1, 8, 14, 14, 14)
      $g.DrawCurve($p1, @([System.Drawing.PointF]::new(6,18),[System.Drawing.PointF]::new(10,16),[System.Drawing.PointF]::new(14,19),[System.Drawing.PointF]::new(18,17)))
    } else {
      $g.FillEllipse($b1, 6, 7, 14, 14)
      $g.FillEllipse($b2, 16, 3, 12, 12)
      $g.FillEllipse($b1, 10, 15, 14, 14)
      $g.DrawCurve($p1, @([System.Drawing.PointF]::new(7,9),[System.Drawing.PointF]::new(12,8),[System.Drawing.PointF]::new(16,10),[System.Drawing.PointF]::new(20,9)))
    }

    $b1.Dispose(); $b2.Dispose(); $p1.Dispose()
  }
  return $bmp
}

Save-Png (Make-GrassTile 0) (Join-Path $root "assets\\tiles\\grass_a.png")
Save-Png (Make-GrassTile 1) (Join-Path $root "assets\\tiles\\grass_b.png")

## --- UI textures ---
function Make-TopBar() {
  $bmp = New-Bitmap 512 64 $true
  With-Graphics $bmp {
    param($g)
    $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(36,0,0,0))
    $fill   = New-Object System.Drawing.SolidBrush $panel
    $stroke = New-Object System.Drawing.Pen -ArgumentList $border, 2
    $hiPen  = New-Object System.Drawing.Pen -ArgumentList ([System.Drawing.Color]::FromArgb(90,255,255,255)), 3

    $pShadow = New-RoundedRectPath 10 10 492 44 14
    $g.FillPath($shadow, $pShadow)
    $pShadow.Dispose()

    $p = New-RoundedRectPath 8 8 492 44 14
    $g.FillPath($fill, $p)
    $g.DrawPath($stroke, $p)
    $p.Dispose()

    $g.DrawLine($hiPen, 22, 16, 490, 16)

    $shadow.Dispose(); $fill.Dispose(); $stroke.Dispose(); $hiPen.Dispose()
  }
  return $bmp
}

function Make-Button() {
  $bmp = New-Bitmap 160 48 $true
  With-Graphics $bmp {
    param($g)
    $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(40,0,0,0))
    $fill   = New-Object System.Drawing.SolidBrush $panel
    $stroke = New-Object System.Drawing.Pen -ArgumentList $border, 2
    $hiPen  = New-Object System.Drawing.Pen -ArgumentList ([System.Drawing.Color]::FromArgb(90,255,255,255)), 3

    $pShadow = New-RoundedRectPath 6 8 148 34 12
    $g.FillPath($shadow, $pShadow)
    $pShadow.Dispose()

    $p = New-RoundedRectPath 4 6 148 34 12
    $g.FillPath($fill, $p)
    $g.DrawPath($stroke, $p)
    $p.Dispose()

    $g.DrawLine($hiPen, 18, 14, 140, 14)

    $shadow.Dispose(); $fill.Dispose(); $stroke.Dispose(); $hiPen.Dispose()
  }
  return $bmp
}

Save-Png (Make-TopBar) (Join-Path $root "assets\\ui\\topbar.png")
Save-Png (Make-Button) (Join-Path $root "assets\\ui\\button.png")

## --- Icons (32x32) ---
function Make-IconWood() {
  $bmp = New-Bitmap 32 32 $true
  With-Graphics $bmp {
    param($g)
    $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(26,0,0,0))
    $g.FillEllipse($shadow, 5, 23, 22, 7)
    $shadow.Dispose()

    $b = New-Object System.Drawing.SolidBrush $wood3
    $g.FillRectangle($b, 6, 14, 18, 6)
    $b.Dispose()

    $b = New-Object System.Drawing.SolidBrush $wood2
    $g.FillRectangle($b, 8, 12, 18, 6)
    $b.Dispose()

    $b = New-Object System.Drawing.SolidBrush $wood4
    $g.FillRectangle($b, 10, 18, 18, 6)
    $b.Dispose()

    $end = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(120,$wood4))
    $g.FillEllipse($end, 22, 13, 5, 5)
    $g.FillEllipse($end, 24, 19, 5, 5)
    $end.Dispose()
  }
  return $bmp
}

function Make-IconFood() {
  $bmp = New-Bitmap 32 32 $true
  With-Graphics $bmp {
    param($g)
    $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(24,0,0,0))
    $g.FillEllipse($shadow, 5, 23, 22, 7)
    $shadow.Dispose()

    $b1 = New-Object System.Drawing.SolidBrush $grassA
    $b2 = New-Object System.Drawing.SolidBrush $grassB
    $g.FillEllipse($b1, 10, 9, 12, 16)
    $g.FillEllipse($b2, 12, 11, 8, 14)
    $b1.Dispose(); $b2.Dispose()

    $tie = New-Object System.Drawing.SolidBrush $wood2
    $g.FillEllipse($tie, 13, 19, 6, 5)
    $tie.Dispose()
  }
  return $bmp
}

function Make-IconGold() {
  $bmp = New-Bitmap 32 32 $true
  With-Graphics $bmp {
    param($g)
    $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(24,0,0,0))
    $g.FillEllipse($shadow, 5, 23, 22, 7)
    $shadow.Dispose()

    $b1 = New-Object System.Drawing.SolidBrush $gold1
    $b2 = New-Object System.Drawing.SolidBrush $gold2
    $g.FillEllipse($b1, 6, 14, 16, 9)
    $g.FillEllipse($b1, 6, 13, 16, 9)
    $g.FillEllipse($b2, 12, 16, 14, 8)
    $g.FillEllipse($b1, 12, 15, 14, 8)
    $b1.Dispose(); $b2.Dispose()
  }
  return $bmp
}

function Make-IconPop() {
  $bmp = New-Bitmap 32 32 $true
  With-Graphics $bmp {
    param($g)
    $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(24,0,0,0))
    $g.FillEllipse($shadow, 5, 23, 22, 7)
    $shadow.Dispose()

    $b1 = New-Object System.Drawing.SolidBrush $blue
    $b2 = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,127,184,207))
    $g.FillEllipse($b1, 9, 8, 10, 10)
    $g.FillEllipse($b2, 17, 10, 8, 8)
    $g.FillEllipse($b1, 6, 16, 18, 10)
    $g.FillEllipse($b2, 13, 17, 14, 9)
    $b1.Dispose(); $b2.Dispose()
  }
  return $bmp
}

function Make-IconStone() {
  $bmp = New-Bitmap 32 32 $true
  With-Graphics $bmp {
    param($g)
    $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(24,0,0,0))
    $g.FillEllipse($shadow, 5, 23, 22, 7)
    $shadow.Dispose()

    $s1 = New-Object System.Drawing.SolidBrush (New-Color "#8f97a1")
    $s2 = New-Object System.Drawing.SolidBrush (New-Color "#b6bdc6")
    $s3 = New-Object System.Drawing.SolidBrush (New-Color "#6f7781")
    $g.FillEllipse($s1, 7, 12, 12, 10)
    $g.FillEllipse($s2, 13, 11, 12, 9)
    $g.FillEllipse($s3, 12, 16, 12, 9)
    $s1.Dispose(); $s2.Dispose(); $s3.Dispose()
  }
  return $bmp
}

Save-Png (Make-IconWood) (Join-Path $root "assets\\icons\\wood.png")
Save-Png (Make-IconFood) (Join-Path $root "assets\\icons\\food.png")
Save-Png (Make-IconGold) (Join-Path $root "assets\\icons\\gold.png")
Save-Png (Make-IconPop) (Join-Path $root "assets\\icons\\population.png")
Save-Png (Make-IconStone) (Join-Path $root "assets\\icons\\stone.png")

function Make-BtnHouse() {
  $bmp = New-Bitmap 32 32 $true
  With-Graphics $bmp {
    param($g)
    $sh = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(22,0,0,0))
    $g.FillEllipse($sh, 6, 24, 20, 6); $sh.Dispose()

    $w = New-Object System.Drawing.SolidBrush $wood2
    $g.FillRectangle($w, 9, 14, 14, 12); $w.Dispose()
    $r = New-Object System.Drawing.SolidBrush $roofR
    $g.FillPolygon($r, @([System.Drawing.Point]::new(8,15),[System.Drawing.Point]::new(16,8),[System.Drawing.Point]::new(24,15),[System.Drawing.Point]::new(24,17),[System.Drawing.Point]::new(8,17)))
    $r.Dispose()
    $d = New-Object System.Drawing.SolidBrush (New-Color "#8f5f3f")
    $g.FillRectangle($d, 14, 18, 4, 8); $d.Dispose()
    $win = New-Object System.Drawing.SolidBrush $blue
    $g.FillRectangle($win, 10, 18, 4, 4); $win.Dispose()
  }
  return $bmp
}

function Make-BtnFarm() {
  $bmp = New-Bitmap 32 32 $true
  With-Graphics $bmp {
    param($g)
    $sh = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(22,0,0,0))
    $g.FillEllipse($sh, 6, 24, 20, 6); $sh.Dispose()

    $f = New-Object System.Drawing.SolidBrush $grassB
    $g.FillRectangle($f, 7, 14, 18, 12); $f.Dispose()
    $pen = New-Object System.Drawing.Pen -ArgumentList ([System.Drawing.Color]::FromArgb(200,$grassC)), 2
    $g.DrawLine($pen, 9, 17, 23, 17)
    $g.DrawLine($pen, 9, 21, 23, 21)
    $pen.Dispose()

    $shed = New-Object System.Drawing.SolidBrush $wood2
    $g.FillRectangle($shed, 20, 11, 6, 7); $shed.Dispose()
    $r = New-Object System.Drawing.SolidBrush $roofR2
    $g.FillPolygon($r, @([System.Drawing.Point]::new(19,12),[System.Drawing.Point]::new(23,9),[System.Drawing.Point]::new(27,12),[System.Drawing.Point]::new(27,14),[System.Drawing.Point]::new(19,14)))
    $r.Dispose()
  }
  return $bmp
}

function Make-BtnSawmill() {
  $bmp = New-Bitmap 32 32 $true
  With-Graphics $bmp {
    param($g)
    $sh = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(22,0,0,0))
    $g.FillEllipse($sh, 6, 24, 20, 6); $sh.Dispose()

    $b = New-Object System.Drawing.SolidBrush $wood2
    $g.FillRectangle($b, 7, 14, 14, 12); $b.Dispose()
    $r = New-Object System.Drawing.SolidBrush $roofR2
    $g.FillPolygon($r, @([System.Drawing.Point]::new(6,15),[System.Drawing.Point]::new(14,10),[System.Drawing.Point]::new(22,15),[System.Drawing.Point]::new(22,17),[System.Drawing.Point]::new(6,17)))
    $r.Dispose()
    $blade = New-Object System.Drawing.SolidBrush (New-Color "#c8d0d6")
    $g.FillEllipse($blade, 10, 18, 6, 6); $blade.Dispose()
    $logs = New-Object System.Drawing.SolidBrush $wood3
    $g.FillEllipse($logs, 20, 18, 7, 4); $logs.Dispose()
  }
  return $bmp
}

function Make-BtnStorage() {
  $bmp = New-Bitmap 32 32 $true
  With-Graphics $bmp {
    param($g)
    $sh = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(22,0,0,0))
    $g.FillEllipse($sh, 6, 24, 20, 6); $sh.Dispose()

    $b = New-Object System.Drawing.SolidBrush $wood2
    $g.FillRectangle($b, 7, 13, 18, 13); $b.Dispose()
    $r = New-Object System.Drawing.SolidBrush $roofR
    $g.FillPolygon($r, @([System.Drawing.Point]::new(6,14),[System.Drawing.Point]::new(16,8),[System.Drawing.Point]::new(26,14),[System.Drawing.Point]::new(26,16),[System.Drawing.Point]::new(6,16)))
    $r.Dispose()
    $d = New-Object System.Drawing.SolidBrush (New-Color "#8f5f3f")
    $g.FillRectangle($d, 14, 18, 7, 8); $d.Dispose()
    $c = New-Object System.Drawing.SolidBrush $wood3
    $g.FillRectangle($c, 8, 20, 4, 4); $c.Dispose()
  }
  return $bmp
}

function Make-BtnMining() {
  $bmp = New-Bitmap 32 32 $true
  With-Graphics $bmp {
    param($g)
    $sh = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(22,0,0,0))
    $g.FillEllipse($sh, 6, 24, 20, 6); $sh.Dispose()

    $stone = New-Object System.Drawing.SolidBrush (New-Color "#9aa2ad")
    $g.FillEllipse($stone, 9, 15, 14, 11); $stone.Dispose()

    $handle = New-Object System.Drawing.SolidBrush $wood3
    $g.FillRectangle($handle, 18, 9, 3, 12); $handle.Dispose()
    $head = New-Object System.Drawing.SolidBrush (New-Color "#c8d0d6")
    $g.FillRectangle($head, 14, 8, 10, 4); $head.Dispose()
  }
  return $bmp
}

function Make-BtnMine() {
  $bmp = New-Bitmap 32 32 $true
  With-Graphics $bmp {
    param($g)
    $sh = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(22,0,0,0))
    $g.FillEllipse($sh, 6, 24, 20, 6); $sh.Dispose()

    $dark = New-Object System.Drawing.SolidBrush (New-Color "#5c6470")
    $g.FillRectangle($dark, 8, 12, 16, 14); $dark.Dispose()
    $ent = New-Object System.Drawing.SolidBrush (New-Color "#8a929e")
    $g.FillRectangle($ent, 10, 14, 12, 10); $ent.Dispose()
    $rail = New-Object System.Drawing.SolidBrush (New-Color "#c8d0d6")
    $g.FillRectangle($rail, 6, 10, 20, 3); $rail.Dispose()
    $cart = New-Object System.Drawing.SolidBrush $wood2
    $g.FillRectangle($cart, 18, 20, 8, 6); $cart.Dispose()
  }
  return $bmp
}

function Make-BtnWall() {
  $bmp = New-Bitmap 32 32 $true
  With-Graphics $bmp {
    param($g)
    $sh = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(22,0,0,0))
    $g.FillEllipse($sh, 6, 24, 20, 6); $sh.Dispose()

    $b1 = New-Object System.Drawing.SolidBrush (New-Color "#9a9ca0")
    $b2 = New-Object System.Drawing.SolidBrush (New-Color "#b8babf")
    $g.FillRectangle($b1, 7, 10, 18, 14); $b1.Dispose()
    $g.FillRectangle($b2, 9, 12, 5, 10); $g.FillRectangle($b2, 16, 12, 5, 10); $b2.Dispose()
    $cap = New-Object System.Drawing.SolidBrush (New-Color "#7a7d82")
    $g.FillRectangle($cap, 7, 8, 18, 3); $cap.Dispose()
  }
  return $bmp
}

Save-Png (Make-BtnHouse) (Join-Path $root "assets\\icons\\btn_house.png")
Save-Png (Make-BtnFarm) (Join-Path $root "assets\\icons\\btn_farm.png")
Save-Png (Make-BtnSawmill) (Join-Path $root "assets\\icons\\btn_sawmill.png")
Save-Png (Make-BtnStorage) (Join-Path $root "assets\\icons\\btn_storage.png")
Save-Png (Make-BtnMining) (Join-Path $root "assets\\icons\\btn_mining.png")
Save-Png (Make-BtnMine) (Join-Path $root "assets\\icons\\btn_mine.png")
Save-Png (Make-BtnWall) (Join-Path $root "assets\\icons\\btn_wall.png")

## --- Building sprites (64x64) ---
function Make-BuildingHouse() {
  $bmp = New-Bitmap 64 64 $true
  With-Graphics $bmp {
    param($g)
    $sh = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(46,0,0,0))
    $g.FillEllipse($sh, 14, 46, 36, 12); $sh.Dispose()

    $w = New-Object System.Drawing.SolidBrush $wood1
    $g.FillRectangle($w, 18, 28, 28, 24)
    $w.Dispose()
    $w2 = New-Object System.Drawing.SolidBrush $wood2
    $g.FillRectangle($w2, 20, 30, 24, 20)
    $w2.Dispose()

    $roof = New-Object System.Drawing.SolidBrush $roofR
    $g.FillPolygon($roof, @([System.Drawing.Point]::new(16,30),[System.Drawing.Point]::new(32,18),[System.Drawing.Point]::new(48,30),[System.Drawing.Point]::new(48,34),[System.Drawing.Point]::new(16,34)))
    $roof.Dispose()

    $door = New-Object System.Drawing.SolidBrush (New-Color "#8f5f3f")
    $g.FillRectangle($door, 28, 36, 8, 16); $door.Dispose()

    $win = New-Object System.Drawing.SolidBrush $blue
    $g.FillRectangle($win, 21, 36, 6, 6); $win.Dispose()
  }
  return $bmp
}

function Make-BuildingFarm() {
  $bmp = New-Bitmap 64 64 $true
  With-Graphics $bmp {
    param($g)
    $sh = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(40,0,0,0))
    $g.FillEllipse($sh, 13, 46, 38, 12); $sh.Dispose()

    $field = New-Object System.Drawing.SolidBrush $grassA
    $g.FillRectangle($field, 12, 28, 40, 22); $field.Dispose()
    $field2 = New-Object System.Drawing.SolidBrush $grassB
    $g.FillRectangle($field2, 14, 30, 36, 18); $field2.Dispose()

    $pen = New-Object System.Drawing.Pen -ArgumentList ([System.Drawing.Color]::FromArgb(200,$grassC)), 2
    $g.DrawCurve($pen, @([System.Drawing.PointF]::new(16,34),[System.Drawing.PointF]::new(24,33),[System.Drawing.PointF]::new(32,35),[System.Drawing.PointF]::new(48,34)))
    $g.DrawCurve($pen, @([System.Drawing.PointF]::new(16,40),[System.Drawing.PointF]::new(24,39),[System.Drawing.PointF]::new(32,41),[System.Drawing.PointF]::new(48,40)))
    $g.DrawCurve($pen, @([System.Drawing.PointF]::new(16,46),[System.Drawing.PointF]::new(24,45),[System.Drawing.PointF]::new(32,47),[System.Drawing.PointF]::new(48,46)))
    $pen.Dispose()

    $shed = New-Object System.Drawing.SolidBrush $wood2
    $g.FillRectangle($shed, 40, 22, 14, 18); $shed.Dispose()
    $r = New-Object System.Drawing.SolidBrush $roofR2
    $g.FillPolygon($r, @([System.Drawing.Point]::new(38,24),[System.Drawing.Point]::new(47,16),[System.Drawing.Point]::new(56,24),[System.Drawing.Point]::new(56,28),[System.Drawing.Point]::new(38,28)))
    $r.Dispose()
  }
  return $bmp
}

function Make-BuildingSawmill() {
  $bmp = New-Bitmap 64 64 $true
  With-Graphics $bmp {
    param($g)
    $sh = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(40,0,0,0))
    $g.FillEllipse($sh, 12, 46, 40, 13); $sh.Dispose()

    $body = New-Object System.Drawing.SolidBrush $wood2
    $g.FillRectangle($body, 14, 26, 30, 24); $body.Dispose()
    $r = New-Object System.Drawing.SolidBrush $roofR2
    $g.FillPolygon($r, @([System.Drawing.Point]::new(12,28),[System.Drawing.Point]::new(29,18),[System.Drawing.Point]::new(46,28),[System.Drawing.Point]::new(46,32),[System.Drawing.Point]::new(12,32)))
    $r.Dispose()

    $blade = New-Object System.Drawing.SolidBrush (New-Color "#c8d0d6")
    $g.FillEllipse($blade, 18, 34, 13, 13); $blade.Dispose()

    $logs1 = New-Object System.Drawing.SolidBrush $wood3
    $g.FillEllipse($logs1, 40, 34, 14, 6); $logs1.Dispose()
    $logs2 = New-Object System.Drawing.SolidBrush $wood4
    $g.FillEllipse($logs2, 38, 40, 16, 6); $logs2.Dispose()
  }
  return $bmp
}

function Make-BuildingStorage() {
  $bmp = New-Bitmap 64 64 $true
  With-Graphics $bmp {
    param($g)
    $sh = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(40,0,0,0))
    $g.FillEllipse($sh, 11, 46, 42, 13); $sh.Dispose()

    $body = New-Object System.Drawing.SolidBrush $wood2
    $g.FillRectangle($body, 14, 24, 36, 28); $body.Dispose()
    $roof = New-Object System.Drawing.SolidBrush $roofR
    $g.FillPolygon($roof, @([System.Drawing.Point]::new(12,26),[System.Drawing.Point]::new(32,14),[System.Drawing.Point]::new(52,26),[System.Drawing.Point]::new(52,30),[System.Drawing.Point]::new(12,30)))
    $roof.Dispose()

    $door = New-Object System.Drawing.SolidBrush (New-Color "#8f5f3f")
    $g.FillRectangle($door, 28, 34, 14, 18); $door.Dispose()

    $crate = New-Object System.Drawing.SolidBrush $wood3
    $g.FillRectangle($crate, 16, 40, 10, 10); $crate.Dispose()
  }
  return $bmp
}

Save-Png (Make-BuildingHouse) (Join-Path $root "assets\\buildings\\house.png")
Save-Png (Make-BuildingFarm) (Join-Path $root "assets\\buildings\\farm.png")
Save-Png (Make-BuildingSawmill) (Join-Path $root "assets\\buildings\\sawmill.png")
Save-Png (Make-BuildingStorage) (Join-Path $root "assets\\buildings\\storage.png")

function Make-BuildingMine() {
  $bmp = New-Bitmap 64 64 $true
  With-Graphics $bmp {
    param($g)
    $sh = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(40,0,0,0))
    $g.FillEllipse($sh, 12, 46, 40, 13); $sh.Dispose()

    $dark = New-Object System.Drawing.SolidBrush (New-Color "#4a5058")
    $g.FillRectangle($dark, 14, 22, 36, 26); $dark.Dispose()
    $face = New-Object System.Drawing.SolidBrush (New-Color "#6a717a")
    $g.FillRectangle($face, 18, 26, 28, 18); $face.Dispose()
    $rail = New-Object System.Drawing.SolidBrush (New-Color "#c8d0d6")
    $g.FillRectangle($rail, 10, 20, 44, 5); $rail.Dispose()
    $ore = New-Object System.Drawing.SolidBrush (New-Color "#8f97a1")
    $g.FillEllipse($ore, 22, 32, 10, 8); $g.FillEllipse($ore, 34, 34, 8, 7); $ore.Dispose()
    $wood = New-Object System.Drawing.SolidBrush $wood2
    $g.FillRectangle($wood, 40, 28, 8, 14); $wood.Dispose()
  }
  return $bmp
}

function Make-BuildingWall() {
  $bmp = New-Bitmap 64 64 $true
  With-Graphics $bmp {
    param($g)
    $sh = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(40,0,0,0))
    $g.FillEllipse($sh, 14, 46, 36, 12); $sh.Dispose()

    $b1 = New-Object System.Drawing.SolidBrush (New-Color "#8e9095")
    $b2 = New-Object System.Drawing.SolidBrush (New-Color "#a8aaaf")
    $g.FillRectangle($b1, 16, 18, 32, 28); $b1.Dispose()
    $g.FillRectangle($b2, 20, 22, 8, 20); $g.FillRectangle($b2, 36, 22, 8, 20); $b2.Dispose()
    $mortar = New-Object System.Drawing.SolidBrush (New-Color "#7a7d82")
    $g.FillRectangle($mortar, 16, 30, 32, 3); $g.FillRectangle($mortar, 28, 22, 3, 24); $mortar.Dispose()
    $cap = New-Object System.Drawing.SolidBrush (New-Color "#6a6d72")
    $g.FillRectangle($cap, 14, 14, 36, 6); $cap.Dispose()
  }
  return $bmp
}

Save-Png (Make-BuildingMine) (Join-Path $root "assets\\buildings\\mine.png")
Save-Png (Make-BuildingWall) (Join-Path $root "assets\\buildings\\wall.png")

Write-Host "Done."

