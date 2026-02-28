param(
  [string]$apkPath = ".\build\app\outputs\apk\release\app-release.apk",
  [string]$bucket = "releases",
  [string]$remotePath = "buffetapp_latest.apk",
  [string]$metaPath = "update.json",
  [string]$projectUrl = "https://<your-project>.supabase.co"
)

if (-not $env:SUPABASE_SERVICE_ROLE_KEY) {
  Write-Host "ERROR: SUPABASE_SERVICE_ROLE_KEY environment variable is required to generate signed URLs." -ForegroundColor Red
  exit 1
}

Write-Host "Subiendo $apkPath a bucket $bucket/$remotePath (privado) ..."

# Subimos el APK (requiere supabase CLI configurado)
supabase storage upload $bucket $apkPath --path $remotePath
if ($LASTEXITCODE -ne 0) {
  Write-Host "Error al subir APK. Verifica supabase CLI y credenciales." -ForegroundColor Red
  exit 1
}

Write-Host "Generando signed-URL para APK..."

$serviceKey = $env:SUPABASE_SERVICE_ROLE_KEY
$signEndpoint = "$projectUrl/storage/v1/object/sign/$bucket"

# Llamamos al endpoint para obtener signed URL (POST with JSON body {"path":"$remotePath","maxAge":3600})
$body = @{ path = $remotePath; maxAge = 86400 } | ConvertTo-Json
try {
  $resp = Invoke-RestMethod -Method Post -Uri $signEndpoint -Body $body -ContentType 'application/json' -Headers @{ Authorization = "Bearer $serviceKey" }
} catch {
  Write-Host "Error al solicitar signed URL: $_" -ForegroundColor Red
  exit 1
}

if (-not $resp || -not $resp.signedURL) {
  Write-Host "No se obtuvo signedURL desde Supabase." -ForegroundColor Red
  exit 1
}

$signedApkUrl = $resp.signedURL

Write-Host "Signed URL generado (expira en 86400s). Generando metadata..."

$versionName = Read-Host "Ingresá versionName (ej: 2.0.1)"
$versionCode = Read-Host "Ingresá versionCode (ej: 20001)"

$meta = @{ 
  versionName = $versionName;
  versionCode = [int]$versionCode;
  apk_url = $signedApkUrl;
  notes = "Cambios desplegados $(Get-Date -Format o)"
}

$metaJson = $meta | ConvertTo-Json -Compress

$tmpMeta = Join-Path $env:TEMP $metaPath
Set-Content -Path $tmpMeta -Value $metaJson -Encoding UTF8

Write-Host "Subiendo metadata $metaPath (público) ..."
supabase storage upload $bucket $tmpMeta --path $metaPath
if ($LASTEXITCODE -ne 0) {
  Write-Host "Error al subir metadata." -ForegroundColor Red
  exit 1
}

Write-Host "Deploy completado. Metadata pública disponible en:" -ForegroundColor Green
Write-Host "$projectUrl/storage/v1/object/public/$bucket/$metaPath"
Write-Host "Signed APK URL (temporal): $signedApkUrl"
