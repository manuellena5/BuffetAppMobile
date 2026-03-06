# 1) Setear la key (una vez por sesión de terminal)
$env:SUPABASE_SERVICE_ROLE_KEY = ""

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
