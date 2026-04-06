# Registro de Cambios Técnicos y Correcciones

## 2026-02-04: Corrección de error "LCL bellow model levels"

### Archivo afectado
`pos_process/derived_quantities.py`

### Descripción del Problema
Durante el post-procesamiento de sondeos, se producía un error crítico cuando el Nivel de Condensación por Ascenso (LCL) calculado tenía una presión mayor que la presión en el nivel más bajo del modelo (superficie). Físicamente, esto implica que el LCL está "bajo tierra".

El error específico era: `CRITICAL: LCL bellow model levels. Non physical situation`.

### Causa
Este fenómeno suele deberse a pequeñas discrepancias numéricas o situaciones donde el aire en superficie está extremadamente cerca de la saturación (HR ~ 100%), haciendo que el cálculo teórico del LCL resulte en una altura infinitesimalmente negativa respecto a la referencia de presión del modelo.

### Solución Implementada
Se modificó la función `get_cumulus_base_top` para incluir una tolerancia de **20 hPa**.

- **Anteriormente:** Si `LCL_presión > Superficie_presión` -> **Error Crítico y Parada**.
- **Actualmente:** Si `LCL_presión > Superficie_presión` pero la diferencia es <= 20 hPa:
    1. Se ajusta la presión del LCL igual a la presión de superficie (Clamping).
    2. Se emite un aviso (Warning) indicando el ajuste.
    3. El proceso continúa asumiendo condensación desde la superficie.

### Impacto en la Salida
1.  **Continuidad:** El script `run_postprocess.py` ya no se interrumpe por este motivo, permitiendo generar los gráficos restantes para ese paso de tiempo.
2.  **Visualización:** En los diagramas Skew-T (plots de sondeos), si ocurre este caso, se visualizará el nivel de condensación comenzando directamente desde el suelo (línea discontinua horizontal). Esto se interpreta meteorológicamente como **niebla** o nubes con base en superficie.
3.  **Datos:** Los cálculos derivados que dependen de la base de la nube (`cu_base`) recibirán un valor válido (presión de superficie) en lugar de un valor nulo, permitiendo que la estimación de "Cumulus" (en la tira lateral del gráfico) muestre nubosidad desde el suelo hacia arriba si las condiciones de flotabilidad lo permiten.
