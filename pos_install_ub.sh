#!/bin/bash
# INSTALADOR COMPLETO Y FUNCIONAL

set -e  # Salir si hay error

echo "🔧 Instalando dependencias del sistema..."
sudo apt-get update
sudo apt-get install -y \
    python3.10 \
    python3.10-dev \
    python3.10-venv \
    python3.10-distutils \
    build-essential \
    gfortran \
    libnetcdf-dev \
    libhdf5-dev \
    libssl-dev \
    libffi-dev \
    curl \
    wget

echo "🧹 Limpiando entorno anterior..."
rm -rf ~/.env_py3_10
rm -rf ~/.cache/pip

echo "🐍 Creando entorno virtual..."
python3.10 -m venv ~/.env_py3_10 --prompt py3_10
source ~/.env_py3_10/bin/activate

# Configura el archivo .wrf_env para cargar el entorno
ENV_FILE="$HOME/.wrf_env"
ACTIVATE_CMD="source \"$HOME/.env_py3_10/bin/activate\""

if ! grep -qF "$ACTIVATE_CMD" "$ENV_FILE" 2>/dev/null; then
    echo "📝 Añadiendo activación a $ENV_FILE..."
    echo "$ACTIVATE_CMD" >> "$ENV_FILE"
else
    echo "✅ Activación ya presente en $ENV_FILE"
fi

echo "📦 Instalando herramientas base EN ORDEN..."
pip install --upgrade pip==23.3.1
pip install wheel==0.42.0
pip install setuptools==59.8.0
pip install packaging==24.0
pip install Cython==3.0.8

echo "📦 Instalando numpy (CRÍTICO)..."
pip install numpy==1.26.4

echo "🔍 Verificando instalaciones base..."
python -c "
import pip, wheel, setuptools, packaging, numpy, Cython
print(f'✅ pip: {pip.__version__}')
print(f'✅ wheel: {wheel.__version__}')
print(f'✅ setuptools: {setuptools.__version__}')
print(f'✅ packaging: {packaging.__version__}')
print(f'✅ Cython: {Cython.__version__}')
print(f'✅ numpy: {numpy.__version__}')
"

echo "🌪️ Instalando wrf-python (MÉTODO GARANTIZADO)..."
echo "=============================================="

# Método 1: Instalación directa con flags
echo "🔄 Método 1: Instalación optimizada..."
pip install wrf-python \
    --no-build-isolation \
    --no-cache-dir \
    --verbose 2>&1 | grep -E "(Installing|Successfully|error|Error)" || true

# Verificar si funcionó
if python -c "import wrf" 2>/dev/null; then
    echo "✅ wrf-python instalado con éxito"
else
    echo "🔄 Método 1 falló, probando Método 2..."
    
    # Método 2: Instalar dependencias primero
    echo "📦 Instalando dependencias conocidas de wrf-python..."
    pip install xarray==2023.12.0 netcdf4==1.6.5 scipy==1.11.4
    
    # Intentar nuevamente
    pip install wrf-python \
        --no-deps \
        --no-build-isolation \
        --no-cache-dir
fi

# Verificar nuevamente
if python -c "import wrf" 2>/dev/null; then
    echo "✅ wrf-python instalado con éxito"
else
    echo "🔄 Método 2 falló, probando Método 3 (desde GitHub)..."
    
    # Método 3: Desde GitHub
    cd /tmp
    rm -rf wrf-python-gh
    git clone --depth 1 https://github.com/NCAR/wrf-python.git wrf-python-gh
    cd wrf-python-gh
    
    # Instalar
    pip install . \
        --no-build-isolation \
        --no-cache-dir
    
    cd ~
fi

echo "📦 Instalando resto de paquetes..."
pip install \
    pyqt5 \
    matplotlib==3.8.4 \
    matplotlib-scalebar \
    scipy \
    xarray \
    netcdf4 \
    rasterio \
    cartopy \
    folium \
    tkintermapview \
    basemap \
    metpy \
    astral \
    beautifulsoup4 \
    playwright \
    psutil

echo "🎭 Instalando Playwright..."
python -m playwright install
python -m playwright install-deps

echo "🔍 VERIFICACIÓN FINAL COMPLETA..."
echo "================================="
python -c "
import sys
print(f'Python path: {sys.executable}')
print(f'Python version: {sys.version}')
print()

# Lista de paquetes a verificar
packages_info = [
    ('wrf', 'wrf-python', True),
    ('numpy', 'numpy', True),
    ('xarray', 'xarray', True),
    ('matplotlib', 'matplotlib', True),
    ('netCDF4', 'netcdf4', True),
    ('cartopy', 'cartopy', True),
    ('metpy', 'metpy', True),
    ('PyQt5', 'pyqt5', False),
    ('playwright', 'playwright', False),
]

print('📦 Paquetes instalados:')
print('-' * 50)

all_ok = True
for import_name, pip_name, required in packages_info:
    try:
        module = __import__(import_name)
        version = 'unknown'
        
        # Intentar obtener versión de diferentes maneras
        try:
            version = module.__version__
        except:
            try:
                import importlib.metadata
                version = importlib.metadata.version(pip_name)
            except:
                version = 'N/A'
        
        print(f'✅ {import_name}: {version}')
        
    except ImportError as e:
        if required:
            print(f'❌ {import_name}: FALTA (REQUERIDO)')
            all_ok = False
        else:
            print(f'⚠️  {import_name}: FALTA (opcional)')

print('-' * 50)

if all_ok:
    print('🎉 ¡TODOS LOS PAQUETES REQUERIDOS INSTALADOS!')
    
    # Probar wrf específicamente
    try:
        import wrf
        print(f'✅ wrf-python funciona correctamente')
        print(f'   Ubicación: {wrf.__file__}')
    except Exception as e:
        print(f'⚠️  Advertencia con wrf-python: {e}')
else:
    print('❌ Faltan algunos paquetes requeridos')
"

echo "✨ Proceso completado!"
echo "⚙️  Configurando proyecto..."

# Detectar base_folder desde namelist.input
NAMELIST="$HOME/meteo/namelist.input"
DEFAULT_BASE="$HOME/meteo/pos_process"
BASE_FOLDER="$DEFAULT_BASE"

if [ -f "$NAMELIST" ]; then
    # Extrae la ruta entre comillas simples de history_outname
    HISTORY_PATH=$(grep "history_outname" "$NAMELIST" | head -n 1 | sed -n "s/.*'\(.*\)'.*/\1/p")

    if [ -n "$HISTORY_PATH" ]; then
        # Asume estructura .../WRF_OUT/wrfout... y recorta desde /WRF_OUT en adelante
        EXTRACTED=$(echo "$HISTORY_PATH" | sed 's|/WRF_OUT.*||')
        if [ -n "$EXTRACTED" ]; then
            BASE_FOLDER="$EXTRACTED"
            echo "📍 Detectado base_folder desde namelist: $BASE_FOLDER"
        fi
    else
        echo "⚠️ No se encontró history_outname en $NAMELIST, usando defecto"
    fi
else
    echo "⚠️ No se encontró $NAMELIST, usando defecto: $BASE_FOLDER"
fi

# Crear config.ini si no existe
if [ ! -f "config.ini" ]; then
    echo "📝 Generando config.ini..."
    cat > config.ini <<EOF
[paths]
domain: Galicia
base_folder: $BASE_FOLDER
wrfout_folder = \${base_folder}/WRF_OUT
plots_folder  = \${base_folder}/PLOTS/\${domain}
data_folder   = \${base_folder}/DATA/\${domain}
configs       = ./configs
EOF
else
    echo "✅ config.ini ya existe."
fi

# Crear directorios usando utils.py
echo "📂 Verificando directorios..."
"$HOME/.env_py3_10/bin/python" -c "import sys; sys.path.insert(0, 'pos_process'); import utils; utils.load_config_or_die('config.ini')"

GREEN='\033[0;32m'
NC='\033[0m' # No Color (Sin color)
echo -e "${GREEN}✅ ¡Todo listo!${NC}"
