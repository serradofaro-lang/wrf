#!/bin/bash
# enviar_ip.sh

# Configuración
URL_REMOTA="https://navegal.es/ip_server.php"
USER="meteowrf"  # Cambia por tu email
HOSTNAME=$(hostname)
LOG="envio_ip.log"

# Función para logging
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" > "$LOG"
}

# Hacer petición con email al servidor remoto
RESPUESTA=$(curl -s -w "\n%{http_code}" --max-time 15 \
    -H "User-Agent: MonitorIP-Ubuntu/1.0" \
    -d "user=$USER" \
    -d "hostname=$HOSTNAME" \
    -d "timestamp=$(date +%s)" \
    "$URL_REMOTA" 2>&1)

HTTP_CODE=$(echo "$RESPUESTA" | tail -n1)
CONTENIDO=$(echo "$RESPUESTA" | sed '$d')

# Verificar respuesta
if [ "$HTTP_CODE" -eq 200 ]; then
    log_message "Petición enviada $URL_REMOTA. Respuesta: $CONTENIDO"
    exit 0
else
    log_message "ERROR: Código HTTP $HTTP_CODE para $EMAIL. Respuesta: $CONTENIDO"
    exit 1
fi
