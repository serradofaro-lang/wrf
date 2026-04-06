#!/bin/bash
RUN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CONFIG_FILE="$(realpath "$RUN_DIR/../config.ini" 2>/dev/null || echo "$RUN_DIR/../config.ini")"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Archivo de configuración no encontrado: $CONFIG_FILE"
    exit 1
fi

export RUN_BY_CRON='True'

SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}" .sh)
LOG_FILE="${RUN_DIR}/logs/${SCRIPT_NAME}.log"
ERR_FILE="${RUN_DIR}/logs/${SCRIPT_NAME}.err"

: > "$LOG_FILE"
: > "$ERR_FILE"

exec 1> "$LOG_FILE"
exec 2> "$ERR_FILE"

cd "$RUN_DIR"

source "$HOME"/.env_py3_10/bin/activate
VENV_PY="$HOME/.env_py3_10/bin/python"
echo "$(date): Using Python: $($VENV_PY --version)"

# Prevent concurrent executions with a lock
LOCKFILE="/tmp/stations_download.lock"
exec 200>"$LOCKFILE"
flock -n 200 || {
    echo "$(date): Another instance is already running. Exiting." >> /tmp/stations_download.log
    exit 1
}

time $VENV_PY download_stations_data.py --config "$CONFIG_FILE"

rm -f "$LOCKFILE"
