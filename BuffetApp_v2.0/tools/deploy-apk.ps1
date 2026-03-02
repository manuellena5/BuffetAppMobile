<#
.SYNOPSIS
  Build APK, upload to Supabase Storage, generate signed-URL, publish update.json
.DESCRIPTION
  Ejecutar desde la raíz del proyecto Flutter.
  Requiere:
    - Supabase CLI logueado
    - $env:SUPABASE_SERVICE_ROLE_KEY seteado
  Uso:
    $env:SUPABASE_SERVICE_ROLE_KEY = "tu_key"
    .\tools\deploy-apk.ps1
    .\tools\deploy-apk.ps1 -SkipBuild           # si ya tenés el APK generado
    .\tools\deploy-apk.ps1 -SignedUrlExpiry 604800  # signed URL de 7 días
#>
param(
  [switch]$SkipBuild,
  [int]$SignedUrlExpiry = 604800  # 7 días por defecto
)

# ── Config ──────────────────────────────────────────────────────
$supabaseCli  = "C:\Users\manuel.ellena\AppData\Local\supabase_windows_amd64\supabase.exe"
$projectUrl   = "https://mncemnlhtgvtubtkvivd.supabase.co"
$bucket       = "releases"
$apkRemote    = "buffetapp_latest.apk"
$metaRemote   = "update.json"
$apkLocal     = ".\build\app\outputs\apk\release\app-release.apk"
# ────────────────────────────────────────────────────────────────

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Validaciones ──
if (-not $env:SUPABASE_SERVICE_ROLE_KEY) {
  Write-Host "ERROR: Seteá SUPABASE_SERVICE_ROLE_KEY antes de ejecutar." -ForegroundColor Red
  Write-Host '  $env:SUPABASE_SERVICE_ROLE_KEY = "tu_key"'
  exit 1
}
if (-not (Test-Path $supabaseCli)) {
  Write-Host "ERROR: No se encontró Supabase CLI en $supabaseCli" -ForegroundColor Red
  exit 1
}

# ── 1) Build APK ──
if (-not $SkipBuild) {
  Write-Host "`n=== Compilando APK release ===" -ForegroundColor Cyan
  flutter build apk --release
  if ($LASTEXITCODE -ne 0) { Write-Host "Error al compilar." -ForegroundColor Red; exit 1 }
}
if (-not (Test-Path $apkLocal)) {
  Write-Host "ERROR: No se encontró APK en $apkLocal" -ForegroundColor Red; exit 1
}

# ── 2) Leer versión desde app_version.dart ──
$versionFile = ".\lib\app_version.dart"
$versionName = "0.0.0"
$versionCode = 0
if (Test-Path $versionFile) {
  $content = Get-Content $versionFile -Raw
  if ($content -match "version\s*=\s*'([^']+)'") { $versionName = $Matches[1] }
  if ($content -match "buildNumber\s*=\s*(\d+)")  { $versionCode = [int]$Matches[1] }
}
Write-Host "Version: $versionName+$versionCode" -ForegroundColor Yellow

# ── 3) Upload APK ──
Write-Host "`n=== Subiendo APK al bucket '$bucket/$apkRemote' ===" -ForegroundColor Cyan
& $supabaseCli storage cp $apkLocal "ss:///$bucket/$apkRemote" --experimental
if ($LASTEXITCODE -ne 0) {
  Write-Host "Error al subir APK. Verificá login y bucket." -ForegroundColor Red; exit 1
}

# ── 4) Generar signed URL via REST ──
Write-Host "`n=== Generando signed URL (expira en ${SignedUrlExpiry}s) ===" -ForegroundColor Cyan
$signBody = @{ expiresIn = $SignedUrlExpiry } | ConvertTo-Json
$signHeaders = @{
  "Authorization" = "Bearer $env:SUPABASE_SERVICE_ROLE_KEY"
  "Content-Type"  = "application/json"
}
$signUri = "$projectUrl/storage/v1/object/sign/$bucket/$apkRemote"

try {
  $signResp = Invoke-RestMethod -Method Post -Uri $signUri -Body $signBody -Headers $signHeaders
} catch {
  Write-Host "Error al solicitar signed URL: $_" -ForegroundColor Red; exit 1
}

if (-not $signResp.signedURL) {
  Write-Host "No se obtuvo signedURL." -ForegroundColor Red; exit 1
}

# La signedURL viene como path relativo; construir URL completa
$signedApkUrl = "$projectUrl/storage/v1$($signResp.signedURL)"
Write-Host "Signed URL: $signedApkUrl" -ForegroundColor Green

# ── 5) Generar y subir update.json ──
Write-Host "`n=== Generando y subiendo update.json ===" -ForegroundColor Cyan
$notes = Read-Host "Notas de la versión (Enter para omitir)"
if ([string]::IsNullOrWhiteSpace($notes)) { $notes = "Actualización $versionName" }

$meta = @{
  versionName = $versionName
  versionCode = $versionCode
  apk_url     = $signedApkUrl
  notes       = $notes
  published   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
} | ConvertTo-Json -Compress

$tmpMeta = Join-Path $env:TEMP $metaRemote
Set-Content -Path $tmpMeta -Value $meta -Encoding UTF8

& $supabaseCli storage cp $tmpMeta "ss:///$bucket/$metaRemote" --experimental
if ($LASTEXITCODE -ne 0) {
  Write-Host "Error al subir metadata." -ForegroundColor Red; exit 1
}

# ── Resumen ──
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Deploy completado!" -ForegroundColor Green
Write-Host "  Version:  $versionName+$versionCode"
Write-Host "  Metadata: $projectUrl/storage/v1/object/public/$bucket/$metaRemote"
Write-Host "  APK URL:  $signedApkUrl"
Write-Host "  Expira:   $SignedUrlExpiry segundos"
Write-Host "========================================" -ForegroundColor Green
