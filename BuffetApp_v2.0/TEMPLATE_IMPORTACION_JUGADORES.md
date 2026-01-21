# Template de Importación de Jugadores/Staff (CSV)

## Formato del archivo CSV

El archivo debe ser CSV (separado por comas) con codificación UTF-8.

### Estructura del archivo

**Primera fila**: Encabezados (obligatorios)
**Filas siguientes**: Datos de cada jugador/staff

## Columnas disponibles

### Columnas OBLIGATORIAS

| Columna | Descripción | Ejemplo | Validaciones |
|---------|-------------|---------|--------------|
| `nombre` | Nombre completo del jugador/staff | Juan Pérez | No puede estar vacío |
| `rol` | Rol en el plantel | JUGADOR | Valores: JUGADOR, DT, AYUDANTE, PF, OTRO |

### Columnas OPCIONALES

| Columna | Descripción | Ejemplo | Valores permitidos |
|---------|-------------|---------|-------------------|
| `alias` | Apodo o alias | El Toto | Texto libre |
| `tipo_contratacion` | Tipo de contratación (solo JUGADOR) | LOCAL | LOCAL, REFUERZO, OTRO (dejar vacío si no aplica) |
| `posicion` | Posición en cancha (solo JUGADOR) | DELANTERO | ARQUERO, DEFENSOR, MEDIOCAMPISTA, DELANTERO, STAFF_CT (dejar vacío si no aplica) |
| `contacto` | Teléfono o email de contacto | +54 9 11 1234-5678 | Texto libre |
| `dni` | Documento de identidad | 12345678 | Solo números |
| `fecha_nacimiento` | Fecha de nacimiento | 1990-05-15 | Formato: YYYY-MM-DD |
| `observaciones` | Notas adicionales | Refuerzo para torneo | Texto libre |

## Valores permitidos por columna

### Columna `rol`
- `JUGADOR` - Jugador del plantel
- `DT` - Director Técnico
- `AYUDANTE` - Ayudante de Campo
- `PF` - Preparador Físico
- `OTRO` - Otro rol

### Columna `tipo_contratacion` (solo para rol=JUGADOR)
- `LOCAL` - Jugador local del club
- `REFUERZO` - Jugador refuerzo/préstamo temporal
- `OTRO` - Otro tipo de contratación
- *(dejar vacío si no es jugador o no aplica)*

### Columna `posicion` (solo para rol=JUGADOR)
- `ARQUERO` - Arquero
- `DEFENSOR` - Defensor
- `MEDIOCAMPISTA` - Mediocampista
- `DELANTERO` - Delantero
- `STAFF_CT` - Staff del Cuerpo Técnico
- *(dejar vacío si no es jugador o no aplica)*

## Ejemplo de archivo CSV

```csv
nombre,rol,alias,tipo_contratacion,posicion,contacto,dni,fecha_nacimiento,observaciones
Juan Pérez,JUGADOR,El Toto,LOCAL,DELANTERO,3512345678,12345678,1995-03-15,Goleador histórico
María González,DT,La Profe,,,3519876543,87654321,1980-07-22,Ex jugadora profesional
Carlos Rodríguez,JUGADOR,Carlitos,REFUERZO,MEDIOCAMPISTA,3518888888,22222222,1998-11-30,Préstamo hasta diciembre
Pedro López,AYUDANTE,,,,,,,Asistente de campo
Ana Martínez,JUGADOR,La Tana,LOCAL,ARQUERO,3517777777,33333333,2000-01-10,
```

## Notas importantes

1. **Codificación**: El archivo debe estar en UTF-8 para soportar caracteres especiales (tildes, ñ, etc.)

2. **Encabezados**: Los nombres de las columnas deben coincidir exactamente (case-sensitive)

3. **Valores vacíos**: 
   - Para columnas opcionales, dejar vacío (sin espacios)
   - NO usar NULL, N/A o guiones

4. **Comas en el texto**: 
   - Si un valor contiene comas, encerrarlo entre comillas dobles
   - Ejemplo: `"López, Juan Carlos"`

5. **Fechas**: 
   - Siempre usar formato ISO: YYYY-MM-DD
   - Ejemplo válido: `1995-03-15`
   - Ejemplo inválido: `15/03/1995` o `15-03-1995`

6. **Roles y valores especiales**:
   - Deben coincidir exactamente con los valores permitidos
   - SON case-sensitive: usar MAYÚSCULAS
   - Ejemplos válidos: `JUGADOR`, `LOCAL`, `DELANTERO`
   - Ejemplos inválidos: `jugador`, `Local`, `delantero`

7. **Duplicados**:
   - No se permiten nombres duplicados
   - El sistema rechazará la importación si encuentra nombres repetidos

## Template vacío para descargar

```csv
nombre,rol,alias,tipo_contratacion,posicion,contacto,dni,fecha_nacimiento,observaciones
```

## Errores comunes

| Error | Causa | Solución |
|-------|-------|----------|
| "Nombre es requerido" | Columna nombre vacía | Completar nombre en todas las filas |
| "Rol inválido" | Valor de rol no permitido | Usar solo: JUGADOR, DT, AYUDANTE, PF, OTRO |
| "Tipo de contratación inválido" | Valor no permitido | Usar solo: LOCAL, REFUERZO, OTRO (o dejar vacío) |
| "Posición inválida" | Valor no permitido | Usar solo: ARQUERO, DEFENSOR, MEDIOCAMPISTA, DELANTERO, STAFF_CT (o dejar vacío) |
| "Fecha inválida" | Formato de fecha incorrecto | Usar formato YYYY-MM-DD |
| "Ya existe una entidad con ese nombre" | Nombre duplicado | Cambiar nombre o usar otro alias |

---

**Versión**: 1.0  
**Última actualización**: Enero 2026  
**Contacto**: Soporte BuffetApp
