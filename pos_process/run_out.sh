#!/bin/bash
# run_out.sh - Monitorea y procesa archivos de salida WRF
set -e
shopt -s nullglob

# Función de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    :
}

# Función de error logging
error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# Función para limpiar recursos al salir
cleanup() {
    # Remover los traps para evitar loops infinitos de llamadas de salida (SIGTERM -> exit -> EXIT trap)
    trap - EXIT INT TERM
    log "Limpiando recursos y terminando ejecución..."

    # Limpiar caches de matplotlib
    rm -rf "/tmp/wrf_mplcache_d01" "/tmp/wrf_mplcache_d02" 2>/dev/null || true

    # Matar todos los procesos hijos (incluyendo python3 web server)
    # Recursivamente matar hijos y nietos
    # Pkill -P kills only direct children. We want to be thorough.
    # Jobs -p lists active jobs.
    local children
    children=$(pgrep -P $$)
    if [ -n "$children" ]; then
        log "Matando procesos hijos: $children"
        # Matamos a los hijos de los hijos primero (nietos)
        for child in $children; do
            pkill -P "$child" 2>/dev/null || true
        done
        # Matamos a los hijos directos
        kill -TERM $children 2>/dev/null || true
        sleep 1
        kill -9 $children 2>/dev/null || true
    fi

    # Cerrar automáticamente el file descriptor al salir
    exec 200>&-

    # Limpiar archivo de bloqueo
    rm -f "$LOCKFILE" 2>/dev/null || true

    # Limpiar archivo STOP si existe
    [ -f "$RUN_DIR/STOP" ] && rm -f "$RUN_DIR/STOP"

    log "Limpieza completada."
    exit 0
}

# ============================================================================
# CONFIGURACIÓN
# ============================================================================

# Función mejorada para leer INI (Soporta = y :, ignora comentarios #, resuelve ${var})
get_config_value() {
    local section="$1"
    local key="$2" 
    
    # 1. Extraer valor crudo (soporta = y :)
    local line=$(sed -n "/^\[$section\]/,/^\[/p" "$CONFIG_FILE" | \
                 grep -E "^[[:space:]]*$key[[:space:]]*[=:]" | \
                 grep -v "^[[:space:]]*#" | \
                 head -1)
    
    if [ -z "$line" ]; then
        echo ""
        return
    fi

    # Limpiar clave y separador, espacios y comillas
    local value=$(echo "$line" | sed -E 's/^[^=:]*[=:][[:space:]]*//' | \
                  sed -e 's/[[:space:]]*$//' | \
                  sed -e "s/^'//" -e "s/'$//" -e 's/^"//' -e 's/"$//')
    
    # 2. Resolver interpolación ${variable} recursivamente
    local loop_count=0
    # Iterar mientras haya patrón ${...} (max 10 pasadas para seguridad)
    while [[ "$value" =~ \$\{([a-zA-Z0-9_]+)\} ]] && [ $loop_count -lt 10 ]; do
        local var_name="${BASH_REMATCH[1]}"
        local var_val=""
        
        # Buscar en el mismo INI (misma sección)
        if [ "$var_name" != "$key" ]; then
             var_val=$(get_config_value "$section" "$var_name")
        fi
        
        # Si no, buscar en variables de entorno
        if [ -z "$var_val" ]; then
            var_val="${!var_name:-}"
        fi
        
        if [ -n "$var_val" ]; then
            # Reemplazar si se encuentra valor
            value="${value//\$\{$var_name\}/$var_val}"
        else
            # Si no se encuentra (está comentada o no existe), IGNORARLA (preservarla).
            # Cambiamos temporalmente a marcas << >> para evitar bucle infinito en el regex
            value="${value//\$\{$var_name\}/<<${var_name}>>}"
        fi
        ((loop_count++))
    done
    
    # Restaurar variables no resueltas (<<var>> -> ${var})
    value=$(echo "$value" | sed -E 's/<<([a-zA-Z0-9_]+)>>/${\1}/g')
    
    echo "$value"
}

RUN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CONFIG_FILE="$(realpath "$RUN_DIR/../config.ini" 2>/dev/null || echo "$RUN_DIR/../config.ini")"

if [ ! -f "$CONFIG_FILE" ]; then
    error "Archivo de configuración no encontrado: $CONFIG_FILE"
    exit 1
fi

export RUN_BY_CRON='True'

# Limpiar archivo STOP si existe
[ -f "$RUN_DIR/STOP" ] && rm -f "$RUN_DIR/STOP"

# Archivos de log
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}" .sh)
LOG_FILE="${RUN_DIR}/${SCRIPT_NAME}.log"
ERR_FILE="${RUN_DIR}/${SCRIPT_NAME}.err"

# Archivo de bloqueo para ejecuciones concurrentes
LOCKFILE="/tmp/wrfout_wrapper.lock"

# ============================================================================
# INICIALIZACIÓN
# ============================================================================

# Guardar copia de seguridad de los logs del día anterior
YESTERDAY=$(TZ=UTC date -d "yesterday" +"%Y%m%d")
BACKUP_LOG_FILE="${RUN_DIR}/${SCRIPT_NAME}_${YESTERDAY}.log"
BACKUP_ERR_FILE="${RUN_DIR}/${SCRIPT_NAME}_${YESTERDAY}.err"

if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
    cp "$LOG_FILE" "$BACKUP_LOG_FILE"
fi
if [ -f "$ERR_FILE" ] && [ -s "$ERR_FILE" ]; then
    cp "$ERR_FILE" "$BACKUP_ERR_FILE"
fi

# Mantenemos solo los últimos 3 archivos de backup antiguos del log y err
find "$RUN_DIR" -maxdepth 1 -name "${SCRIPT_NAME}_*.log" -type f -mtime +3 -exec rm -f {} \;
find "$RUN_DIR" -maxdepth 1 -name "${SCRIPT_NAME}_*.err" -type f -mtime +3 -exec rm -f {} \;

# Limpiar archivos de log previos
: > "$LOG_FILE"
: > "$ERR_FILE"

# Interactivo: Mostrar en pantalla y en log
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$ERR_FILE")

# Adquirir bloqueo para ejecución única
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    error "Otra instancia ya se está ejecutando. Saliendo."
    exit 1
fi

# Configurar traps para limpieza SOLO DESPUÉS de adquirir el bloqueo
trap cleanup EXIT INT TERM

log "========================================================================"
log "Iniciando $0"
log "Directorio de ejecución: $RUN_DIR"

# Configurar Python
VENV_PY="$HOME/.env_py3_10/bin/python"
if [ ! -f "$VENV_PY" ]; then
    error "No se encontró el intérprete Python: $VENV_PY"
    exit 1
fi

PY_VERSION=$("$VENV_PY" --version 2>&1)
log "Usando Python: $PY_VERSION"

# ============================================================================
# CONFIGURACIÓN DE RUTAS
# ============================================================================

WPS_DOMAIN=$(get_config_value "paths" "domain")
[ -z "$WPS_DOMAIN" ] && WPS_DOMAIN="Galicia"

# Obtener directorio de ejecución WRF
WRF_RUN_DIR=$(get_config_value "paths" "wrf_run_dir")
WRFOUT_FOLDER=$(get_config_value "paths" "wrfout_folder")
[ -z "$WRFOUT_FOLDER" ] && WRFOUT_FOLDER=$WRF_RUN_DIR


log "Dominio WPS: $WPS_DOMAIN"
log "Directorio WRF output: $WRFOUT_FOLDER"
log "Directorio WRF run: $WRF_RUN_DIR"

# Verificar que el directorio existe
if [ ! -d "$WRFOUT_FOLDER" ]; then
    error "Directorio WRF output no existe: $WRFOUT_FOLDER"
    exit 1
fi

# Obtener configuración de horario
SCHEDULE_START=$(get_config_value "schedule" "start_hour")
SCHEDULE_END=$(get_config_value "schedule" "end_hour")
[ -z "$SCHEDULE_START" ] && SCHEDULE_START=0
[ -z "$SCHEDULE_END" ] && SCHEDULE_END=23
log "Horario de procesamiento: $SCHEDULE_START - $SCHEDULE_END"
 
# Obtener configuración de limpieza
CLEANUP_DAYS=$(get_config_value "processing" "cleanup_days")
[ -z "$CLEANUP_DAYS" ] && CLEANUP_DAYS=3
log "Días de mantenimiento (cleanup): $CLEANUP_DAYS"

# Tiempos de espera (en segundos)
# Intervalo de bucle
LOOP_SLEEP=$(get_config_value "processing" "loop_sleep")
[ -z "$LOOP_SLEEP" ] && LOOP_SLEEP=5
log "Intervalo de bucle: ${LOOP_SLEEP}s"

PARALLEL_PROCESSING=$(get_config_value "processing" "parallel_processing")
[ -z "$PARALLEL_PROCESSING" ] && PARALLEL_PROCESSING="false"
log "Procesamiento paralelo: $PARALLEL_PROCESSING"

# Obtener configuración FTP
FTP_URL=$(get_config_value "ftp" "url")
FTP_USER=$(get_config_value "ftp" "user")
FTP_PASS=$(get_config_value "ftp" "password")
FTP_REMOTE=$(get_config_value "ftp" "remote_path")
FTP_ENABLED=$(get_config_value "ftp" "enabled")

if [ "${FTP_ENABLED,,}" == "false" ]; then
    log "FTP DESHABILITADO localmente"
elif [ -n "$FTP_URL" ]; then
    log "FTP configurado y habilitado: $FTP_URL"
else
    log "FTP no configurado (solo procesamiento local)"
fi

# Configurar rutas adicionales
PROCESSED_DIR="$WRFOUT_FOLDER/processed"
FAILED_DIR="$WRFOUT_FOLDER/failed"

MAIN_SCRIPT="$RUN_DIR/run_postprocess.py"
MANIFEST_SCRIPT="$RUN_DIR/gen_manifest.py"

# Verificar scripts necesarios
for script in "$MAIN_SCRIPT" "$MANIFEST_SCRIPT"; do
    if [ ! -f "$script" ]; then
        error "Script no encontrado: $script"
        exit 1
    fi
done

WEB_VIEWER_DIR=$(get_config_value "paths" "web_viewer_dir")
[ -z "$WEB_VIEWER_DIR" ] && WEB_VIEWER_DIR="${RUN_DIR}/../web_viewer"

# Crear directorios necesarios
mkdir -p "$WEB_VIEWER_DIR" "$PROCESSED_DIR" "$FAILED_DIR"

PLOTS_FOLDER=$(get_config_value "paths" "plots_folder")
[ -z "$PLOTS_FOLDER" ] && PLOTS_FOLDER="PLOTS$WPS_DOMAIN"

DATA_FOLDER=$(get_config_value "paths" "data_folder")
[ -z "$DATA_FOLDER" ] && DATA_FOLDER="DATA$WPS_DOMAIN"

# Limpieza de meteogramas al inicio (para evitar acumulación de días previos)
if [ -n "$DATA_FOLDER" ] && [ -d "$DATA_FOLDER/meteograms" ]; then
    log "Limpiando meteogramas antiguos en: $DATA_FOLDER/meteograms"
    # Borrar contenido recursivamente
    rm -rf "$DATA_FOLDER/meteograms"/* 2>/dev/null || true
fi

# Limpieza de logs
if [ -d "$RUN_DIR/logs" ]; then
    log "Limpiando logs antiguos en: $RUN_DIR/logs"
    rm -rf "$RUN_DIR/logs"/* 2>/dev/null || true
fi

# Limpieza general de archivos antiguos (mantener T + 2 días previos)
CLEANUP_SCRIPT="$RUN_DIR/cleanup_meteo.py"
if [ -f "$CLEANUP_SCRIPT" ]; then
    log "Ejecutando limpieza de archivos antiguos (mantenimiento: $CLEANUP_DAYS días)..."
    $VENV_PY "$CLEANUP_SCRIPT" --config "$CONFIG_FILE" >> "$LOG_FILE" 2>&1 || log "Advertencia: Falló limpieza de archivos antiguos"

else
    error "Script de limpieza no encontrado: $CLEANUP_SCRIPT"
fi

# Cola de reintentos para uploads fallidos
declare -a UPLOAD_RETRY_QUEUE=()
UPLOAD_ERROR_DETECTED=false

# ============================================================================
# FUNCIONES DE UTILIDAD
# ============================================================================
 
extract_hour_from_filename() {
    local filename="$1"
    local hour
    
    if [[ "$filename" =~ _([0-9]{2}):[0-9]{2}:[0-9]{2}$ ]]; then
        hour="${BASH_REMATCH[1]}"
    elif [[ "$filename" =~ _([0-9]{2})[^0-9]?$ ]]; then
        hour="${BASH_REMATCH[1]}"
    else
        local basename_no_ext="${filename%.*}"
        if [[ "$basename_no_ext" =~ ([0-9]{2})$ ]]; then
            hour="${BASH_REMATCH[1]}"
        else
            echo ""
            return
        fi
    fi
    
    if [[ "$hour" =~ ^[0-9]{2}$ ]] && [ "$hour" -ge 0 ] && [ "$hour" -le 23 ] 2>/dev/null; then
        echo "$((10#$hour))"
    else
        echo ""
    fi
}

# Mantiene los slashes (/) sin codificar
urlencode() {
    local data
    data=$(printf "%s" "$1" | sed -e 's/ /%20/g' \
        -e 's/!/%21/g' \
        -e 's/"/%22/g' \
        -e 's/#/%23/g' \
        -e 's/\$/%24/g' \
        -e 's/&/%26/g' \
        -e "s/'/%27/g" \
        -e 's/(/%28/g' \
        -e 's/)/%29/g' \
        -e 's/\*/%2A/g' \
        -e 's/+/%2B/g' \
        -e 's/,/%2C/g' \
        -e 's/-/%2D/g' \
        -e 's/\./%2E/g' \
        -e 's/:/%3A/g' \
        -e 's/;/%3B/g' \
        -e 's/</%3C/g' \
        -e 's/=/%3D/g' \
        -e 's/>/%3E/g' \
        -e 's/?/%3F/g' \
        -e 's/@/%40/g' \
        -e 's/\[/%5B/g' \
        -e 's/\\/%5C/g' \
        -e 's/\]/%5D/g' \
        -e 's/\^/%5E/g' \
        -e 's/`/%60/g' \
        -e 's/{/%7B/g' \
        -e 's/|/%7C/g' \
        -e 's/}/%7D/g' \
        -e 's/~/%7E/g')
    echo "$data"
}

upload_file() {
    local file="$1"
    local raw_path="$2" # Ruta destino en el servidor (ej: /web/PLOTS/...)

    # Limpiar dobles slashes en el path (ej: //web -> /web)
    raw_path=$(echo "$raw_path" | sed 's|//|/|g')
    
    # Codificar URL (preservando slashes) usando Python
    local encoded_path
    encoded_path=$(urlencode "$raw_path")
    
    # URL Final: ftp://host + path codificado
    local dest_url="${FTP_URL}${encoded_path}"
    
    # Intentar subida con curl
    local curl_out
    if curl_out=$(curl --ftp-ssl-reqd --insecure --ftp-pasv --ftp-create-dirs \
            -T "$file" \
            "$dest_url" \
            --user "${FTP_USER}:${FTP_PASS}" \
            --connect-timeout 3 \
            --max-time 8 \
            --retry 1 \
            --retry-delay 1 \
            --silent --show-error 2>&1); then
        return 0
    else
        error "Error de conexión al subir $(basename "$file"): Servidor no accesible"
        # Marcar que hubo un error de red
        UPLOAD_ERROR_DETECTED=true
        return 1
    fi    
}

# Función para gestionar el manifiesto y subir resultados
manage_manifest() {
    local upload_minutes="$1"
    [ -z "$upload_minutes" ] && upload_minutes=480 # Default 8h
    UPLOAD_ERROR_DETECTED=false
    
    log "Generando manifiesto..."
    # Pasar ruta del config explícitamente
    if $VENV_PY "$MANIFEST_SCRIPT" --config "$CONFIG_FILE"; then
        log "Manifiesto generado correctamente"        

        if [ "${FTP_ENABLED,,}" == "false" ]; then 
            return 0
        fi
        # Si no hay credenciales o FTP está deshabilitado, no intentar subir nada
        if [ -z "$FTP_URL" ]; then
            log "No hay credenciales FTP configuradas, omitiendo subidas"
            return 0
        fi        
        
        # Subir manifiesto
        local manifest_file="$WEB_VIEWER_DIR/manifest.json"
        if [ -f "$manifest_file" ]; then
            if upload_file "$manifest_file" "/${FTP_REMOTE}/manifest.json"; then
                log "✅ Manifest subido correctamente"
            else
                # Verificar si manifest ya está en cola para evitar duplicados
                local manifest_entry="$manifest_file|/${FTP_REMOTE}/manifest.json"
                local already_queued=false
                
                for entry in "${UPLOAD_RETRY_QUEUE[@]}"; do
                    if [ "$entry" = "$manifest_entry" ]; then
                        already_queued=true
                        break
                    fi
                done
                
                if [ "$already_queued" = false ]; then
                    log "⚠️ Error al subir manifest, agregando a cola de reintentos"
                    UPLOAD_RETRY_QUEUE+=("$manifest_entry")
                else
                    log "⚠️ Error al subir manifest (ya en cola de reintentos)"
                fi
            fi
        fi
        
    else
        if [ "${FTP_ENABLED,,}" == "false" ]; then 
            return 0
        fi
        # Si no hay credenciales o FTP está deshabilitado, no intentar subir nada
        if [ -z "$FTP_URL" ]; then
            log "No hay credenciales FTP configuradas, omitiendo subidas"
            return 0
        fi   
        error "Fallo al generar manifiesto (pero se intentará subir gráficos)"
    fi
  
    # Subir gráficos recientes (independientemente del resultado del manifest)
    # Plots están en: $WRFOUT_FOLDER/$PLOTS_FOLDER/$WPS_DOMAIN/
    # Estructura: YYYYMMDD/archivo.webp
        
    local plots_root
    if [[ "$PLOTS_FOLDER" == /* ]]; then
        plots_root="$PLOTS_FOLDER"
    else
        plots_root="$WRFOUT_FOLDER/$PLOTS_FOLDER"
    fi
    if [ -d "$plots_root" ]; then
        
        # Buscar archivos modificados recientemente
        local -a recent_files=()
        while IFS= read -r -d $'\0' file; do
            recent_files+=("$file")
        done < <(find "$plots_root" -type f -mmin -"$upload_minutes" -name "*.webp" -print0)
        
        log "Encontrados ${#recent_files[@]} gráficos nuevos/modificados."
        
        local uploaded=0
        local queued=0
        
        # Pre-calcular el prefijo de subida basado en los dos últimos niveles de PLOTS_FOLDER
        # para coincidir con la lógica de gen_manifest.py (p.parent.name/p.name)
        local plots_folder_name=$(basename "$PLOTS_FOLDER")
        local plots_parent_name=$(basename "$(dirname "$PLOTS_FOLDER")")
        local upload_prefix="${plots_parent_name}/${plots_folder_name}"
        
        for f in "${recent_files[@]}"; do
            local raw_path
            
            # Calcular ruta relativa del archivo respecto a PLOTS_FOLDER
            # Si f es /ruta/PLOTS/Galicia/2023/file.webp y PLOTS_FOLDER es /ruta/PLOTS/Galicia
            # file_relative_part será /2023/file.webp
            local file_relative_part="${f#$PLOTS_FOLDER}"
            
            # Construir ruta remota: /web/PLOTS/Galicia/2023/file.webp
            raw_path="/${FTP_REMOTE}/${upload_prefix}${file_relative_part}"
            
            # Limpiar posibles dobles slashes
            raw_path=$(echo "$raw_path" | sed 's|//|/|g')

            # Si ya hubo un error, agregar directamente a la cola
            if [ "$UPLOAD_ERROR_DETECTED" = true ]; then                 
                UPLOAD_RETRY_QUEUE+=("$f|$raw_path")
                queued=$((queued + 1))
                continue
            fi
            
            # Intentar subir             
            if upload_file "$f" "$raw_path"; then
                uploaded=$((uploaded + 1))
            else
                # Error detectado, agregar este y marcar para detener uploads
                UPLOAD_RETRY_QUEUE+=("$f|$raw_path")
                queued=$((queued + 1))
                log "⚠️ Error de red detectado. Deteniendo uploads. Archivos restantes se agregarán a cola."
                # Marcar error para que archivos restantes se agreguen a cola
                UPLOAD_ERROR_DETECTED=true
            fi
        done
        
        if [ $uploaded -gt 0 ] || [ $queued -gt 0 ]; then
            log "Subidos: $uploaded, En cola para reintento: $queued"
        fi
    fi
    
    return 0
}

# Función para reintentar subidas fallidas
retry_failed_uploads() {
    if [ ${#UPLOAD_RETRY_QUEUE[@]} -eq 0 ]; then
        return 0
    fi
    
    local queue_file="$WRFOUT_FOLDER/upload_queue.txt"
    
    log "========================================================================"
    log "Reintentando subida de ${#UPLOAD_RETRY_QUEUE[@]} archivo(s) en cola..."
    
    # Resetear flag de error para permitir reintentos
    UPLOAD_ERROR_DETECTED=false
    
    local success=0
    local failed=0
    
    for entry in "${UPLOAD_RETRY_QUEUE[@]}"; do
        # Parsear entrada: "archivo|ruta_destino"
        local file="${entry%%|*}"
        local dest_path="${entry#*|}"
        
        if [ ! -f "$file" ]; then
            log "⚠️ Archivo no encontrado, omitiendo: $(basename "$file")"
            failed=$((failed + 1))
            continue
        fi
        
        log "Reintentando: $(basename "$file")..."
        if upload_file "$file" "$dest_path"; then
            log "✅ Subido exitosamente: $(basename "$file")"
            success=$((success + 1))    
        else
            log "❌ Fallo nuevamente: $(basename "$file")"
            failed=$((failed + 1))
            # Si falla el primer reintento, detener para no saturar
            if [ $failed -eq 1 ]; then
                log "⚠️ Primer reintento falló. Deteniendo reintentos para evitar saturación."
                break
            fi
        fi
    done
    
    log "Resultado de reintentos: $success exitosos, $failed fallidos"
    
    # Guardar archivos fallidos en cola persistente
    if [ $failed -gt 0 ]; then
        local -a failed_files=()
        local processed=0
        
        for entry in "${UPLOAD_RETRY_QUEUE[@]}"; do
            local file="${entry%%|*}"
            
            # Si ya procesamos 'success' archivos exitosos, el resto son fallidos
            if [ $processed -ge $success ]; then
                failed_files+=("$entry")
            else
                # Verificar si este archivo fue exitoso
                if [ -f "$file" ]; then
                    processed=$((processed + 1))
                fi
            fi
        done
        
        # Guardar archivos fallidos en archivo persistente
        if [ ${#failed_files[@]} -gt 0 ]; then
            {
                for entry in "${failed_files[@]}"; do
                    echo "$entry"
                done
            } > "$queue_file"
            
            log "💾 Guardados ${#failed_files[@]} archivo(s) en cola persistente: $queue_file"
            log "   Ejecuta 'retry_uploads.sh' cuando se resuelva el problema de conexión."
        fi
    else
        # Si todos fueron exitosos, eliminar archivo de cola si existe
        if [ -f "$queue_file" ]; then
            rm -f "$queue_file"
            log "✅ Cola persistente eliminada (todos los archivos subidos exitosamente)"
        fi
    fi
    
    log "========================================================================"
}


# Función para procesar archivos en paralelo CON TIMEOUT
process_files() {
    local -a files_to_process=("$@")
    local -a pids=()
    local failed=0
    local timeout=300  # 5 minutos máximo por proceso
    
    log "Iniciando procesamiento de ${#files_to_process[@]} archivo(s) (timeout: ${timeout}s)..."
    local start_time=$(date +%s)
    
    # Procesar todos los archivos en paralelo
    for i in "${!files_to_process[@]}"; do
        local file="${files_to_process[$i]}"
        local filename=$(basename "$file")
        # Extraer el dominio (d01, d02...) del nombre para que MPLCONFIGDIR sea único por dominio
        local domain_str=$(echo "$filename" | grep -o 'd[0-9][0-9]' || echo "dXX")
        log "Procesando $filename"
        (
            export MPLCONFIGDIR="/tmp/wrf_mplcache_${domain_str}_$$"
            export MPLBACKEND="Agg"
            mkdir -p "$MPLCONFIGDIR"
            timeout $timeout $VENV_PY "$MAIN_SCRIPT" "$file" --config "$CONFIG_FILE"
        ) &
        local pid=$!
        pids[$i]=$pid
        CHILD_PIDS="$CHILD_PIDS $pid"
    done
    
    # Esperar a que todos los procesos terminen
    for i in "${!pids[@]}"; do
        local pid=${pids[$i]}
        local file_to_process="${files_to_process[$i]}"
        
        if wait $pid; then
            local exit_code=$?
            if [ $exit_code -eq 0 ]; then
                log "✅ Procesamiento exitoso para: $(basename "$file_to_process")"
                [ -n "$PROCESSED_DIR" ] && mv "$file_to_process" "$PROCESSED_DIR/" 2>/dev/null || error "No se pudo mover a PROCESSED_DIR"
            elif [ $exit_code -eq 124 ]; then
                error "⏰ TIMEOUT en procesamiento de: $(basename "$file_to_process")"
                failed=$((failed + 1))
                [ -n "$FAILED_DIR" ] && mv "$file_to_process" "$FAILED_DIR/" 2>/dev/null || error "No se pudo mover a FAILED_DIR"
            else
                error "❌ Error en procesamiento (código $exit_code) de: $(basename "$file_to_process")"
                failed=$((failed + 1))
                [ -n "$FAILED_DIR" ] && mv "$file_to_process" "$FAILED_DIR/" 2>/dev/null || error "No se pudo mover a FAILED_DIR"
            fi
        else
            error "❌ Falló estrepitosamente el procesamiento de: $(basename "$file_to_process")"
            failed=$((failed + 1))
            [ -n "$FAILED_DIR" ] && mv "$file_to_process" "$FAILED_DIR/" 2>/dev/null || error "No se pudo mover a FAILED_DIR"
        fi
        
        # Remover PID de la lista de subprocesos
        CHILD_PIDS=$(echo "$CHILD_PIDS" | sed "s/$pid//")
        # Limpieza de temporales
        local domain_str=$(echo "$(basename "$file_to_process")" | grep -o 'd[0-9][0-9]' || echo "dXX")
        rm -rf "/tmp/wrf_mplcache_${domain_str}_$$" 2>/dev/null || true
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log "Procesamiento completado en ${duration} segundos"
    
    # Calcular tiempo y realizar UNA ÚNICA llamada para manifest
    local upload_minutes=$(( (duration + 15 + 59) / 60 ))
    [ "$upload_minutes" -lt 1 ] && upload_minutes=1
        
    if [ "$failed" -lt ${#files_to_process[@]} ]; then # Si todos fallaron, ni lo subas
        if ! manage_manifest "$upload_minutes"; then
            log "⚠️ Advertencia: Falló la subida de archivos al FTP después del grupo paralelo"
        fi
    fi
    
    if [ "$failed" -eq 0 ]; then
        log "Ciclo de procesamiento exitoso"
    else
        log "Ciclo de procesamiento completado con $failed errores"
    fi
    
    [ "$failed" -eq 0 ]
}

# ============================================================================
# BUCLE PRINCIPAL DE MONITOREO
# ============================================================================

log "Iniciando monitoreo de archivos WRF en: $WRFOUT_FOLDER"
log "Archivos procesados se moverán a: $PROCESSED_DIR"
log "Archivos fallidos se moverán a: $FAILED_DIR"
log "Directorio de ejecución WRF: $WRF_RUN_DIR"
log "Modo: output_ready_flag (buscando archivos wrfoutReady*)"
log "Crea archivo STOP para terminar"

# Eliminar flags wrfoutReady anteriores para evitar procesados falsos
log "Limpiando flags."
rm -f "$WRF_RUN_DIR"/wrfoutReady_d*
log "Flags limpios."

# Eliminar cola persistente si existe (nuevo procesado = contexto limpio)
QUEUE_FILE="$WRFOUT_FOLDER/upload_queue.txt"
if [ -f "$QUEUE_FILE" ]; then
    log "========================================================================"
    log "�️  Eliminando cola persistente de ejecución anterior..."
    rm -f "$QUEUE_FILE"
    log "✅ Cola eliminada. Iniciando procesado limpio."
    log "========================================================================"
fi

while true; do

    # 1. Buscar TODOS los flags wrfoutReady_d*
    flags=()
    while IFS= read -r -d $'\0' f; do
        flags+=("$f")
    done < <(find "$WRF_RUN_DIR" -maxdepth 1 -name "wrfoutReady_d*" -type f -printf "%T@ %p\0" 2>/dev/null | sort -z -n | cut -z -d' ' -f2-)

    if [ ${#flags[@]} -gt 0 ]; then
        # Si se exige paralelo y de momento solo ha caído 1 flag, esperamos al siguiente ciclo
        if [ "${PARALLEL_PROCESSING,,}" == "true" ] && [ ${#flags[@]} -eq 1 ]; then
            # Esperamos callados al resto de dominios
            :
        else
            valid_files=()
        
            for ready_file in "${flags[@]}"; do
                ready_filename=$(basename "$ready_file")
                # Derivar el nombre del archivo wrfout correspondiente
                wrfout_filename=$(echo "$ready_filename" | sed 's/^wrfoutReady_/wrfout_/')
                wrfout_file="$WRFOUT_FOLDER/$wrfout_filename"

                log "Encontrado: $wrfout_filename"
                rm -f "$ready_file"

                # Verificar horario
                hour=$(extract_hour_from_filename "$wrfout_file")
                if [ -z "$hour" ] || [ "$hour" -lt "$SCHEDULE_START" ] || [ "$hour" -gt "$SCHEDULE_END" ]; then
                    [ -z "$hour" ] && error "Hora inválida en $wrfout_file" || log "Fuera de horario ($hour)"
                    log "Moviendo $wrfout_filename a PROCESSED (fuera de horario)..."
                    if ! mv "$wrfout_file" "$PROCESSED_DIR/" 2>/dev/null; then
                        mv "$wrfout_file" "$FAILED_DIR/" 2>/dev/null
                    fi
                    continue
                fi

                # Añadir a la cola válida para procesar en grupo o serie
                valid_files+=("$wrfout_file")
            done
            
            if [ ${#valid_files[@]} -gt 0 ]; then
                if [ "${PARALLEL_PROCESSING,,}" == "true" ] && [ ${#valid_files[@]} -gt 1 ]; then
                    # Procesar el lote acumulado en paralelo
                    process_files "${valid_files[@]}" || true  
                else
                    # Modo Secuencial
                    for f in "${valid_files[@]}"; do
                        process_files "$f" || true
                    done
                fi
            fi
        
        fi
    fi
    # 3. Comprobar si existe archivo STOP para salir
    if [ -f "$RUN_DIR/STOP" ]; then
         # Solo salir si no quedan flags por procesar (doble check rápido)
         count=$(find "$WRF_RUN_DIR" -maxdepth 1 -name "wrfoutReady_d*" 2>/dev/null | wc -l)
         if [ "$count" -eq 0 ]; then
             log "Archivo STOP detectado y no hay flags pendientes. Finalizando..."
             break
         fi
    fi

    sleep "$LOOP_SLEEP"
done

# ============================================================================
# FINALIZACIÓN
# ============================================================================

log "Archivo STOP detectado. Finalizando ejecución..."

# Intentar subir archivos en cola de reintentos antes de salir
if [ -n "$FTP_URL" ] && [ "${FTP_ENABLED,,}" != "false" ]; then
    retry_failed_uploads
fi

log "$(basename "$0") finalizado exitosamente"
log "================================================"

exit 0
