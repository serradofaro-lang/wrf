#!/bin/bash
# run_server.sh - WRF Web Viewer Server Manager

RUN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PARENT_DIR="$(dirname "$RUN_DIR")"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# Function to read config.ini    
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

# Function to find PLOTS directory
find_plots_dir() {
    local wrfout_dir="$1" # Optional fallback
    
    # 1. Priority: Confi.ini (Already interpolated and absolute)
    local plots_folder=$(get_config_value "paths" "plots_folder")
    
    if [ -n "$plots_folder" ]; then
        # Assume it points to a specific domain inside PLOTS, take dirname
        local parent_dir=$(dirname "$plots_folder")
        if [ -d "$parent_dir" ]; then
            echo "$parent_dir"
            return 0
        fi
    fi
    return 1
}

# Function to setup PLOTS symlink
setup_plots_link() {
    log "Setting up PLOTS symlink..."
    
    # Try to find PLOTS dir directly first (using config.ini)
    local plots_dir=$(find_plots_dir)
    
    if [ -z "$plots_dir" ] || [ ! -d "$plots_dir" ]; then
        error "Directorio PLOTS no encontrado! Revisa config.ini (paths.plots_folder)"
        return 1
    fi
    
    log "Directorio PLOTS encontrado: $plots_dir"
    
    # Determine link name based on directory name (e.g., PLOTS or plots)
    local link_name=$(basename "$plots_dir")
    
    # Create or update symlink
    local link_path="$RUN_DIR/$link_name"
    
    if [ -L "$link_path" ]; then
        local current_target=$(readlink -f "$link_path")
        if [ "$current_target" = "$plots_dir" ]; then
            log "Symlink '$link_name' is correct -> $plots_dir"
            return 0
        else
            log "Updating symlink '$link_name': $current_target -> $plots_dir"
            rm -f "$link_path"
        fi
    elif [ -e "$link_path" ]; then
        log "Removing existing non-symlink file/dir: $link_path"
        rm -rf "$link_path"
    fi
    
    # Create the symlink
    ln -sfn "$plots_dir" "$link_path"
    
    if [ -L "$link_path" ]; then
        log "Symlink created successfully: $link_path -> $plots_dir"
        return 0
    else
        error "Failed to create symlink at $link_path"
        return 1
    fi
}

# Function to stop web server
stop_web_server() {
    log "Stopping web server..."
    
    # Find all python http.server processes
    local pids=$(ps aux | grep -E "python3 -m http\.server" | grep -v grep | awk '{print $2}')
    
    if [ -z "$pids" ]; then
        log "No web server processes found"
        return 0
    fi
    
    log "Found web server PIDs: $pids"
    
    # Kill processes gracefully
    kill $pids 2>/dev/null
    sleep 2
    
    # Force kill if still running
    local still_running=$(ps aux | grep -E "python3 -m http\.server" | grep -v grep | awk '{print $2}')
    if [ -n "$still_running" ]; then
        log "Force killing remaining processes: $still_running"
        kill -9 $still_running 2>/dev/null
        sleep 1
    fi
    
    # Verify all stopped
    if ! ps aux | grep -E "python3 -m http\.server" | grep -v grep >/dev/null; then
        log "Web server stopped successfully"
        return 0
    else
        error "Failed to stop all web server processes"
        return 1
    fi
}

# Function to clean up symlinks and temporary files
cleanup() {
    log "Cleaning up..."
    
    # Remove any symlinks except config.ini
    find "$RUN_DIR" -maxdepth 1 -type l -print | while read link; do
        if [ "$(basename "$link")" != "config.ini" ]; then
             log "Removing symlink: $(basename "$link")"
             rm -f "$link"
        fi
    done
    
    # Remove server log file
    if [ -f "$RUN_DIR/web_server.log" ]; then
        log "Removing server log file"
        rm -f "$RUN_DIR/web_server.log"
    fi
    
    # Remove nohup.out if exists
    if [ -f "$RUN_DIR/nohup.out" ]; then
        log "Removing nohup.out"
        rm -f "$RUN_DIR/nohup.out"
    fi
    
    log "Cleanup completed"
}

# Function to show server status
show_status() {
    log "Checking server status..."
    
    # Check for running servers
    local running_servers=$(ps aux | grep -E "python3 -m http\.server" | grep -v grep)
    
    if [ -n "$running_servers" ]; then
        echo "========================================"
        log "Web server is RUNNING"
        echo "----------------------------------------"
        echo "$running_servers"
        echo "----------------------------------------"
        
        # Show ports in use
        local ports=$(echo "$running_servers" | grep -o "8[0-9][0-9][0-9]" | sort -u)
        for port in $ports; do
            log "Access at: http://localhost:$port/"
        done
        echo "========================================"
        return 0
    else
        log "Web server is NOT running"
        return 1
    fi
}

# Function to start web server
start_web_server() {
    local port=8000
    local web_server_log="$RUN_DIR/web_server.log"
    
    # Check if server is already running
    if show_status >/dev/null 2>&1; then
        if [ "$FORCE_RESTART" = "true" ]; then
            log "Server is running, restarting..."
            stop_web_server
            sleep 2
        else
            log "Server is already running (use -f to restart)"
            return 0
        fi
    fi
    
    # Check RUN_DIR contents
    log "Starting web server from: $RUN_DIR"
    log "Web files available:"
    find "$RUN_DIR" -maxdepth 1 \( -name "*.html" -o -name "*.css" -o -name "*.js" \) | sed "s|$RUN_DIR/||" | while read file; do
        log "  $file"
    done
    
    # Check PLOTS/plots symlink
    local plots_link=""
    if [ -L "$RUN_DIR/PLOTS" ]; then plots_link="PLOTS"; fi
    if [ -L "$RUN_DIR/plots" ]; then plots_link="plots"; fi
    
    if [ -n "$plots_link" ]; then
        local plots_target=$(readlink -f "$RUN_DIR/$plots_link")
        log "$plots_link symlink points to: $plots_target"
    else
        log "Warning: PLOTS/plots symlink not found"
    fi
    
    # Start the server
    log "Starting web server on port $port..."
    
    # Clear old log
    > "$web_server_log"
    
    # Start server in background
    (cd "$RUN_DIR" && \
     nohup python3 -m http.server $port > "$web_server_log" 2>&1 &)
    
    sleep 3
    
    # Check if server started
    if ps aux | grep -E "python3 -m http\.server.*$port" | grep -v grep >/dev/null; then
        local pid=$(ps aux | grep -E "python3 -m http\.server.*$port" | grep -v grep | awk '{print $2}' | head -1)
        log "Web server started successfully (PID: $pid)"
        
        # Test server access
        sleep 2
        if command -v curl >/dev/null 2>&1; then
            if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/" | grep -q "200\|301\|302"; then
                log "Server test: SUCCESS"
            else
                log "Server test: May have issues"
            fi
        fi
        
        log "Access URL: http://localhost:$port/"
        log "Log file: $web_server_log"
        return 0
    else
        error "Failed to start web server"
        error "Check log: $web_server_log"
        return 1
    fi
}

# Function to show usage
show_usage() {
    echo "WRF Web Viewer Server Manager"
    echo "============================="
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  start     Start the web server (default command)"
    echo "  stop      Stop the web server"
    echo "  restart   Restart the web server"
    echo "  status    Show server status"
    echo "  clean     Clean up symlinks and temporary files"
    echo "  help      Show this help message"
    echo ""
    echo "Options for 'start' command:"
    echo "  [DIR]     Directory containing PLOTS folder"
    echo "  -f        Force restart if server is running"
    echo ""
    echo "Examples:"
    echo "  $0 start                   # Start server using namelist.input"
    echo "  $0 start /path/to/wrfout   # Start with specific directory"
    echo "  $0 start -f                # Force restart server"
    echo "  $0 stop                    # Stop server"
    echo "  $0 restart                 # Restart server"
    echo "  $0 status                  # Check server status"
    echo "  $0 clean                   # Clean up files"
    echo ""
}

# Main execution
COMMAND="start"
FORCE_RESTART=false
CUSTOM_DIR=""

# Parse command
if [ $# -gt 0 ]; then
    case "$1" in
        start|stop|restart|status|clean|help)
            COMMAND="$1"
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            # If first argument is a directory, use it as custom dir
            if [ -d "$1" ]; then
                CUSTOM_DIR="$1"
                shift
            else
                error "Unknown command: $1"
                show_usage
                exit 1
            fi
            ;;
    esac
fi

# Parse remaining arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force)
            FORCE_RESTART=true
            shift
            ;;
        *)
            # Assume it's a directory
            if [ -d "$1" ]; then
                CUSTOM_DIR="$1"
            else
                error "Invalid argument or directory not found: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Execute command
case "$COMMAND" in
    start)
        echo "========================================"
        log "Starting WRF Web Viewer Server"
        echo "========================================"
        
        # Setup PLOTS symlink
        if ! setup_plots_link "$CUSTOM_DIR"; then
            log "Warning: PLOTS symlink not configured, web viewer may not work properly"
        fi
        
        # Start server
        if start_web_server; then
            echo "========================================"
            log "Server started successfully!"
            log "Open browser to: http://localhost:8000/"
            echo "========================================"
        else
            error "Failed to start server"
            exit 1
        fi
        ;;
    
    stop)
        echo "========================================"
        log "Stopping WRF Web Viewer Server"
        echo "========================================"
        
        if stop_web_server; then
            log "Server stopped successfully"
            
            # Optional: cleanup after stopping
            if [ "$FORCE_RESTART" = "true" ]; then
                cleanup
            fi
        else
            error "Failed to stop server"
            exit 1
        fi
        ;;
    
    restart)
        echo "========================================"
        log "Restarting WRF Web Viewer Server"
        echo "========================================"
        
        FORCE_RESTART=true
        if stop_web_server; then
            sleep 2
            if setup_plots_link "$CUSTOM_DIR"; then
                if start_web_server; then
                    log "Server restarted successfully"
                else
                    error "Failed to restart server"
                    exit 1
                fi
            fi
        fi
        ;;
    
    status)
        show_status
        ;;
    
    clean)
        echo "========================================"
        log "Cleaning up WRF Web Viewer"
        echo "========================================"
        
        # Stop server first if running
        if show_status >/dev/null 2>&1; then
            log "Stopping server before cleanup..."
            stop_web_server
            sleep 2
        fi
        
        cleanup
        log "Cleanup completed successfully"
        ;;
    
    help)
        show_usage
        ;;
    
    *)
        error "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac

exit 0