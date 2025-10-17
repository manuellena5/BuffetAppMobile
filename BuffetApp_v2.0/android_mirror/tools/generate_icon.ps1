param(
  [string]$Source = '..\..\cdm_mitre_white_app_256.png',
  [string]$Dest = '..\assets\icons\app_icon_foreground.png',
  [int]$Canvas = 1024,
  [double]$ContentScale = 0.72
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

Write-Host "Generating icon..."
$srcPath = Resolve-Path $Source
$destDir = Split-Path $Dest -Parent
if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }
$dstPath = Join-Path (Resolve-Path $destDir) (Split-Path $Dest -Leaf)

$bmp = New-Object System.Drawing.Bitmap ($Canvas, $Canvas, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::White)
$img = [System.Drawing.Image]::FromFile($srcPath)

$scale = [Math]::Min(($Canvas * $ContentScale) / $img.Width, ($Canvas * $ContentScale) / $img.Height)
$targetW = [int]($img.Width * $scale)
$targetH = [int]($img.Height * $scale)
$x = [int](($Canvas - $targetW) / 2)
$y = [int](($Canvas - $targetH) / 2)

$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($img, $x, $y, $targetW, $targetH)

$bmp.Save($dstPath, [System.Drawing.Imaging.ImageFormat]::Png)

$g.Dispose()
$bmp.Dispose()
$img.Dispose()

Write-Host "Icon foreground generated at $dstPath"
