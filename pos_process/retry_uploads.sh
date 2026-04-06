#!/bin/bash
# retry_uploads.sh - Reintentar subida de archivos desde cola persistente
set -e

# Directorio de este script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Función de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

get_config_value() {
    local section="$1"
    local key="$2"
    local config_file="${3:-../config.ini}"
    
    # 1. Extraer valor crudo (soporta = y :)
    local line=$(sed -n "/^\[$section\]/,/^\[/p" "$config_file" | \
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
             var_val=$(get_config_value "$section" "$var_name" "$config_file")
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

# Leer configuración
WRFOUT_DIR=$(get_config_value "paths" "wrfout_folder")

if [ -z "$WRFOUT_DIR" ]; then
    error "No se encuenta wrfout_folder en config.ini"
    exit 1
fi

# FTP credentials
FTP_URL=$(get_config_value "ftp" "url" || echo "")
FTP_USER=$(get_config_value "ftp" "user" || echo "")
FTP_PASS=$(get_config_value "ftp" "password" || echo "")

if [ -z "$FTP_URL" ] || [ -z "$FTP_USER" ] || [ -z "$FTP_PASS" ]; then
    error "Credenciales FTP no configuradas en config.ini"
    exit 1
fi

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

# ============================================================================
# FUNCIÓN DE SUBIDA
# ============================================================================

upload_file() {
    local file="$1"
    local raw_path="$2"

    # Limpiar dobles slashes
    raw_path=$(echo "$raw_path" | sed 's|//|/|g')
    
    # Codificar URL
    local encoded_path
    encoded_path=$(urlencode "$raw_path")
    
    local dest_url="${FTP_URL}${encoded_path}"
    
    # Intentar subida
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
        error "Error al subir $(basename "$file"): $curl_out"
        return 1
    fi
}

# ============================================================================
# PROCESAMIENTO DE COLA
# ============================================================================

QUEUE_FILE="$WRFOUT_DIR/upload_queue.txt"

if [ ! -f "$QUEUE_FILE" ]; then
    log "No hay archivos en cola para subir."
    log "Archivo de cola no encontrado: $QUEUE_FILE"
    exit 0
fi

# Leer cola
mapfile -t queue_entries < "$QUEUE_FILE"
total=${#queue_entries[@]}

if [ $total -eq 0 ]; then
    log "Cola vacía, eliminando archivo."
    rm -f "$QUEUE_FILE"
    exit 0
fi

log "========================================================================"
log "Reintentando subida de $total archivo(s) desde cola persistente..."
log "========================================================================"

success=0
failed=0
failed_entries=()

for entry in "${queue_entries[@]}"; do
    # Parsear: "archivo|ruta_destino"
    file="${entry%%|*}"
    dest_path="${entry#*|}"
    
    if [ ! -f "$file" ]; then
        log "⚠️  Archivo no encontrado, omitiendo: $(basename "$file")"
        failed=$((failed + 1))
        continue
    fi
    
    log "Subiendo: $(basename "$file")..."
    if upload_file "$file" "$dest_path"; then
        log "✅ Subido exitosamente: $(basename "$file")"
        success=$((success + 1))
    else
        log "❌ Fallo: $(basename "$file")"
        failed=$((failed + 1))
        failed_entries+=("$entry")
    fi
done

log "========================================================================"
log "Resultado: $success exitosos, $failed fallidos de $total total"
log "========================================================================"

# Actualizar archivo de cola
if [ ${#failed_entries[@]} -gt 0 ]; then
    {
        for entry in "${failed_entries[@]}"; do
            echo "$entry"
        done
    } > "$QUEUE_FILE"
    log "💾 Quedan ${#failed_entries[@]} archivo(s) en cola persistente"
else
    rm -f "$QUEUE_FILE"
    log "🎉 Todos los archivos subidos exitosamente. Cola eliminada."
fi

exit 0
