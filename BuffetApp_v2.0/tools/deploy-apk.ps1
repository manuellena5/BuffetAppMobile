<#
.SYNOPSIS
  Compila el APK de release, lo sube a Supabase Storage (bucket releases)
  y genera update.json con signed-URL para descarga segura.

.DESCRIPTION
  Usa REST API de Supabase Storage (no requiere Supabase CLI).
  Requiere variable de entorno SUPABASE_SERVICE_ROLE_KEY.

.PARAMETER SkipBuild
  Si se pasa, omite la compilación del APK (usa el último compilado).

.PARAMETER SignedUrlExpiry
  Expiración del signed-URL en segundos (default: 604800 = 7 días).

.EXAMPLE
  # Compilar + subir + generar metadata
  .\tools\deploy-apk.ps1

  # Solo subir (sin recompilar)
  .\tools\deploy-apk.ps1 -SkipBuild

  # Signed URL de 30 días
  .\tools\deploy-apk.ps1 -SignedUrlExpiry 2592000
#>
param(
  [switch]$SkipBuild,
  [int]$SignedUrlExpiry = 604800,
  [string]$Notes = ""
)

# ── Configuración ──────────────────────────────────────────────
$projectUrl = "https://mncemnlhtgvtubtkvivd.supabase.co"
$bucket     = "releases"
$serviceKey = $env:SUPABASE_SERVICE_ROLE_KEY

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $serviceKey) {
  Write-Host "ERROR: Variable de entorno SUPABASE_SERVICE_ROLE_KEY no definida." -ForegroundColor Red
  Write-Host '  Ejecuta: $env:SUPABASE_SERVICE_ROLE_KEY = "tu_key"' -ForegroundColor Yellow
  exit 1
}

# ── Leer versión desde app_version.dart ────────────────────────
$versionFile = Join-Path $PSScriptRoot "..\lib\app_version.dart"
if (-not (Test-Path $versionFile)) {
  Write-Host "ERROR: No se encontró lib/app_version.dart" -ForegroundColor Red
  exit 1
}

$versionContent = Get-Content $versionFile -Raw
$versionName = [regex]::Match($versionContent, "version\s*=\s*'([^']+)'").Groups[1].Value
$buildNumber = [regex]::Match($versionContent, "buildNumber\s*=\s*(\d+)").Groups[1].Value

if (-not $versionName -or -not $buildNumber) {
  Write-Host "ERROR: No se pudo leer version o buildNumber de app_version.dart" -ForegroundColor Red
  exit 1
}

Write-Host "Version: $versionName (build $buildNumber)" -ForegroundColor Cyan

# ── Compilar APK ───────────────────────────────────────────────
# Usa --split-per-abi para generar APKs más livianos (< 50MB, límite free Supabase).
# Por defecto sube arm64-v8a (tablets modernas). Para tablets viejas usar armeabi-v7a.
$apkPath = Join-Path $PSScriptRoot "..\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"

if (-not $SkipBuild) {
  Write-Host "`n=== Compilando APK release (split-per-abi) ===" -ForegroundColor Cyan
  Push-Location (Join-Path $PSScriptRoot "..")
  flutter build apk --release --split-per-abi
  $exitCode = $LASTEXITCODE
  Pop-Location

  if ($exitCode -ne 0) {
    Write-Host "ERROR: flutter build apk falló." -ForegroundColor Red
    exit 1
  }
}

if (-not (Test-Path $apkPath)) {
  Write-Host "ERROR: No se encontró APK en $apkPath" -ForegroundColor Red
  exit 1
}

$apkSize = (Get-Item $apkPath).Length
Write-Host "APK listo: $apkPath ($([math]::Round($apkSize / 1MB, 2)) MB)" -ForegroundColor Green

# ── Nombre remoto del APK ─────────────────────────────────────
$remoteName = "buffetapp_v${versionName}_b${buildNumber}.apk"

# ── Subir APK via REST API ─────────────────────────────────────
Write-Host "`n=== Subiendo APK a $bucket/$remoteName ===" -ForegroundColor Cyan

$uploadUri = "$projectUrl/storage/v1/object/$bucket/$remoteName"
$uploadHeaders = @{
  "Authorization" = "Bearer $serviceKey"
  "Content-Type"  = "application/vnd.android.package-archive"
  "x-upsert"      = "true"
}

try {
  Invoke-RestMethod -Uri $uploadUri -Method Post -Headers $uploadHeaders -InFile $apkPath
  Write-Host "APK subido correctamente." -ForegroundColor Green
} catch {
  Write-Host "ERROR al subir APK: $_" -ForegroundColor Red
  exit 1
}

# ── Generar signed-URL para el APK ─────────────────────────────
Write-Host "`n=== Generando signed URL (expira en ${SignedUrlExpiry}s) ===" -ForegroundColor Cyan

$signUri  = "$projectUrl/storage/v1/object/sign/$bucket/$remoteName"
$signBody = @{ expiresIn = $SignedUrlExpiry } | ConvertTo-Json
$signHeaders = @{
  "Authorization" = "Bearer $serviceKey"
  "Content-Type"  = "application/json"
}

try {
  $signResult = Invoke-RestMethod -Uri $signUri -Method Post -Headers $signHeaders -Body $signBody
  $signedPath = $signResult.signedURL
  if (-not $signedPath) {
    Write-Host "ERROR: respuesta de sign no contiene signedURL" -ForegroundColor Red
    Write-Host ($signResult | ConvertTo-Json) -ForegroundColor Yellow
    exit 1
  }
  $signedUrl = "$projectUrl/storage/v1$signedPath"
  Write-Host "Signed URL generada." -ForegroundColor Green
} catch {
  Write-Host "ERROR al generar signed-URL: $_" -ForegroundColor Red
  exit 1
}

# ── Calcular fecha de expiración legible ───────────────────────
$expiresAt = (Get-Date).AddSeconds($SignedUrlExpiry).ToString("yyyy-MM-dd HH:mm:ss")

# ── Pedir notas de versión ─────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($Notes)) {
  if ([Environment]::UserInteractive -and [Console]::In) {
    try { $Notes = Read-Host "Notas de la version (Enter para omitir)" } catch { $Notes = "" }
  }
}
if ([string]::IsNullOrWhiteSpace($Notes)) { $Notes = "Actualizacion v$versionName (build $buildNumber)" }
$notes = $Notes

# ── Crear y subir update.json ──────────────────────────────────
Write-Host "`n=== Subiendo update.json ===" -ForegroundColor Cyan

$updateJson = @{
  versionName = $versionName
  versionCode = [int]$buildNumber
  apk_url     = $signedUrl
  apk_size    = $apkSize
  notes       = $notes
  signed_url_expires_at = $expiresAt
  published   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
} | ConvertTo-Json -Depth 3

$tempJson = Join-Path $env:TEMP "update.json"
$updateJson | Out-File -Encoding utf8 $tempJson

$jsonUploadUri = "$projectUrl/storage/v1/object/$bucket/update.json"
$jsonHeaders = @{
  "Authorization" = "Bearer $serviceKey"
  "Content-Type"  = "application/json"
  "x-upsert"      = "true"
}

try {
  Invoke-RestMethod -Uri $jsonUploadUri -Method Post -Headers $jsonHeaders -InFile $tempJson
  Write-Host "update.json subido correctamente." -ForegroundColor Green
} catch {
  Write-Host "ERROR al subir update.json: $_" -ForegroundColor Red
  exit 1
}

Remove-Item $tempJson -ErrorAction SilentlyContinue

# ── Resumen final ──────────────────────────────────────────────
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  DEPLOY COMPLETO" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Version:       $versionName (build $buildNumber)"
Write-Host "  APK remoto:    $bucket/$remoteName"
Write-Host "  APK tamanio:   $([math]::Round($apkSize / 1MB, 2)) MB"
Write-Host "  Signed URL:    expira $expiresAt"
Write-Host "  Metadata:      $projectUrl/storage/v1/object/public/$bucket/update.json"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nLos dispositivos pueden buscar actualizaciones desde la app." -ForegroundColor Yellow
