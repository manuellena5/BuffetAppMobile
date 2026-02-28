param(
  [string]$apkPath = ".\build\app\outputs\apk\release\app-release.apk",
  [string]$bucket = "releases",
  [string]$remotePath = "buffetapp_latest.apk",
  [string]$metaPath = "update.json",
  [string]$projectUrl = "https://<your-project>.supabase.co"
)

Write-Host "Subiendo $apkPath a bucket $bucket/$remotePath ..."

# Requiere supabase CLI configurado y logueado
supabase storage upload $bucket $apkPath --path $remotePath
if ($LASTEXITCODE -ne 0) {
  Write-Host "Error al subir APK. Verifica supabase CLI y credenciales." -ForegroundColor Red
  exit 1
}

Write-Host "APK subido. Generando metadata ($metaPath)..."

$versionName = Read-Host "Ingresá versionName (ej: 2.0.1)"
$versionCode = Read-Host "Ingresá versionCode (ej: 20001)"

$apkPublicUrl = "$projectUrl/storage/v1/object/public/$bucket/$remotePath"

$meta = @{
  versionName = $versionName
  versionCode = [int]$versionCode
  apk_url = $apkPublicUrl
  notes = "Cambios desplegados $(Get-Date -Format o)"
}

$metaJson = $meta | ConvertTo-Json -Compress

$tmpMeta = Join-Path $env:TEMP $metaPath
Set-Content -Path $tmpMeta -Value $metaJson -Encoding UTF8

Write-Host "Subiendo metadata $metaPath ..."
supabase storage upload $bucket $tmpMeta --path $metaPath
if ($LASTEXITCODE -ne 0) {
  Write-Host "Error al subir metadata." -ForegroundColor Red
  exit 1
}

Write-Host "Deploy completado. URLs públicas:" -ForegroundColor Green
Write-Host "APK: $apkPublicUrl"
Write-Host "Metadata: $projectUrl/storage/v1/object/public/$bucket/$metaPath"
