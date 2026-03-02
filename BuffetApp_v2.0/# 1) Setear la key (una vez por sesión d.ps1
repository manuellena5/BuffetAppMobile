# 1) Setear la key (una vez por sesión de terminal)
$env:SUPABASE_SERVICE_ROLE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1uY2VtbmxodGd2dHVidGt2aXZkIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MTA1OTk3MiwiZXhwIjoyMDc2NjM1OTcyfQ.QCixSuT7-qErBcL0yRNI4ythBptnT4xTKO9g0lP_Zqg"

# 2) Compilar + subir + generar metadata
.\tools\deploy-apk.ps1


# Solo subir (sin recompilar, usa el último APK)
.\tools\deploy-apk.ps1 -SkipBuild

# Con notas personalizadas (evita el prompt interactivo)
.\tools\deploy-apk.ps1 -Notes "Fix impresión USB y mejoras en reportes"

# Signed URL de 30 días en vez de 7
.\tools\deploy-apk.ps1 -SignedUrlExpiry 2592000

# Combinar todo
.\tools\deploy-apk.ps1 -SkipBuild -Notes "Hotfix cierre de caja" -SignedUrlExpiry 2592000Are