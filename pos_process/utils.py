#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import logging
LG = logging.getLogger(f'main.{__name__}')
LGp = logging.getLogger(f'perform.{__name__}')

import os
here = os.path.dirname(os.path.realpath(__file__))
HOME = os.getenv('HOME')
from configparser import ConfigParser, ExtendedInterpolation
from os.path import expanduser
from pathlib import Path
import sys
import datetime as dt
fmt =  '%Y-%m-%d_%H:%M:%S'

REQUIRED_SECTIONS = {
    'paths': ['domain', 'configs']
}

def check_directory(path, create=True):
   """
   Check if a folder exists, and optionally create it if it does not.
   ___ Parameters ___
   path: [str] The directory path to check
   create: [bool] Whether to create the directory if it does not exist
   ___ Returns ___
   bool: True if the directory exists or was created successfully, False
         otherwise
   """
   path = str(path)  # ensure compatibility with Path objects
   if os.path.isdir(path):
      LG.debug(f'Folder {path} already existed')
      return True
   if create:
      try:
         LG.debug(f'Creating folder: {path}')
         os.makedirs(path, exist_ok=True)
         LG.info(f'Created folder: {path}')
         return True
      except OSError as e:
         LG.critical(f"Failed to create directory '{path}': {e}")
         return False
   return False

# from netCDF4 import Dataset (Moved to local scope)

def get_GFSbatch(path):
   """
   DEPRECATED: Read the GFS batch from batch.txt. 
   Kept for backward compatibility but moving towards metadata extraction.
   """
   fmt = '%d/%m/%Y-%H:%M'
   try:
      with open(path,'r') as f:
         gfs_batch = f.read().strip()
         gfs_batch = dt.datetime.strptime(gfs_batch, fmt)
   except:
      LG.warning(f'Unable to determine GFS batch from {path}')
      gfs_batch = '???'
   return gfs_batch

def get_batch_from_metadata(fname):
   """
   Extract SIMULATION_START_DATE from wrfout file attributes.
   """
   try:
      from netCDF4 import Dataset
      with Dataset(fname) as nc:
         start_date_str = nc.getncattr('SIMULATION_START_DATE')
         # Format: YYYY-MM-DD_HH:MM:SS
         batch = dt.datetime.strptime(start_date_str, '%Y-%m-%d_%H:%M:%S')
         return batch
   except Exception as e:
      LG.error(f"Failed to extract batch from metadata of {fname}: {e}")
      return dt.datetime.now() # Fallback to current time

def get_domain(fname):
   return fname.name.replace('wrfout_', '').split('_')[0]

def file2date(fname):
   date = fname.name.split('_')[-2:]
   date = '_'.join(date)
   return dt.datetime.strptime(date,fmt)

def date2file(date,domain,folder):
   return f'{folder}/wrfout_{domain}_{date.strftime(fmt)}'

def load_config_or_die(fname=None, create_dirs=True):
   """
   Carga y valida el archivo principal de configuración (config.ini). 
   Falla de manera ruidosa (sys.exit) si faltan campos o secciones obligatorias.
   
   Args:
       fname (str): Ruta al archivo config.ini. Si es None, busca un nivel por encima.
       create_dirs (bool): Si es True, asegura y crea físicamente las carpetas de salida en disco.
       
   Returns:
       dict: Un diccionario de Python con las rutas maestras absolutas necesarias para el postprocesado.
   """
   # 1. Resolver el archivo de configuración si no se indica la ruta
   if fname is None or fname == "{here}/config.ini":
       fname = os.path.join(here, "..", "config.ini")
       
   # Obtener la ruta absoluta real para manejar correctamente rutas relativas hijas
   config_path = Path(fname).expanduser().resolve()
   base_dir = config_path.parent  

   # 2. Iniciar el parser de configuración soportando interpolación (variables ${})
   config = ConfigParser(interpolation=ExtendedInterpolation())
   config.read(fname)

   # 3. Validar las secciones y campos requeridos estrictamente
   for section, keys in REQUIRED_SECTIONS.items():
      if section not in config:
         LG.critical(f"[ERROR] Falta la sección: [{section}] en {fname}")
         sys.exit(1)
      for key in keys:
         if key not in config[section]:
            msg = f"[ERROR] Falta la clave '{key}' en la sección [{section}] de {fname}"
            LG.critical(msg)
            sys.exit(1)

   # 4. Leer el dominio meteorológico actual
   domain = config["paths"]["domain"]
   
   # 5. Averiguar la carpeta principal de datos de WRF (wrfout_folder)
   wrfout_folder = None
   if "wrfout_folder" in config["paths"]:
       wrfout_folder = expanduser(config["paths"]["wrfout_folder"])
   
   if not wrfout_folder:
       LG.critical("No se pudo determinar wrfout_folder partiendo de config.ini")
       sys.exit(1)

   wrfout_folder  = Path(wrfout_folder).resolve()
   
   # Forzar retrospectivamente la variable en la configuración parseada,
   # por si alguna otra ruta dependía de interpolar ${wrfout_folder}
   if not config.has_option("paths", "wrfout_folder"):
       config.set("paths", "wrfout_folder", str(wrfout_folder))

   # 6. Calcular la ruta a la carpeta de Gráficos (PLOTS)
   if config.has_option("paths", "plots_folder"):
       p = Path(expanduser(config["paths"]["plots_folder"]))
       if not p.is_absolute():
           plots_folder = wrfout_folder / p
       else:
           plots_folder = p
   else:
       plots_folder = wrfout_folder / "PLOTS" / domain
       
   # 7. Calcular la ruta a la carpeta de Datos postprocesados (DATA)
   if config.has_option("paths", "data_folder"):
       p = Path(expanduser(config["paths"]["data_folder"]))
       if not p.is_absolute():
           data_folder = wrfout_folder / p
       else:
           data_folder = p
   else:
       data_folder = wrfout_folder / "DATA" / domain


   # 8. Calcular la ruta a los sub-archivos de configuración secundaria
   raw_configs_path = config["paths"]["configs"]
   configs_folder = (base_dir / raw_configs_path).expanduser().resolve()
   
   # 9. Compilar el diccionario maestro con todos los directorios del programa
   mydict = {
         'wrfout_folder'  : wrfout_folder,
         "plots_folder"   : plots_folder,
         "data_folder"    : data_folder,
         "configs_folder" : configs_folder,
         "data_stations"  : data_folder / 'stations', 
         "plots_stations" : plots_folder / 'stations',
   }

   # 10. Si toca crear directorios, asegurar que existen en el servidor
   for label, path in mydict.items():
      if create_dirs:
         check_directory(path)
         
   # 11. Validar que los archivos de ploteos y zoom existan siempre
   plots_path = configs_folder / 'plots.ini'
   zooms_path = configs_folder / 'zooms.ini'
   for path in [plots_path, zooms_path]:
      if not path.exists():
         LG.critical(f"El archivo obligatorio {path} no se encuentra presente")
         sys.exit(1)
         
   # Adjuntar estos archivos también al diccionario final
   mydict['plots_ini'] = plots_path
   mydict['zooms_ini'] = zooms_path
   
   return mydict


def load_zooms(zoom_file, domain=None):
    """
    Load zoom definitions from an INI file and filter by WRF domain.

    Parameters
    ----------
    zoom_file : [str or Path] Path to the zooms.ini file.
    domain : [str] optional. If specified, only return zooms whose 'parent'
                   matches the domain (e.g. 'd02').
    Returns
    -------
    dict: Dictionary of zoom_name -> (left, right, bottom, top)
    """
    config = ConfigParser()
    config.read(zoom_file)

    zooms = {}
    for section in config.sections():
        parent = config[section].get("parent", "").strip()
        if (domain is None) or (parent == domain):
            bounds = tuple(map(float, [
                config[section]["left"],
                config[section]["right"],
                config[section]["bottom"],
                config[section]["top"]
            ]))
            zooms[section] = bounds

    return zooms

###############################################################################
def pretty_print_var(data):
   """
   Pretty-print summary for a WRF xarray.DataArray variable.
   """
   summary = {"Description": data.attrs.get("description", "N/A"),
              "Name": data.name,
              "Units": data.attrs.get("units", "N/A"),
              "Shape": data.shape,
              "Dimensions": data.dims,
              "No coord dims": list(set(data.dims) - set(data.coords)),
              "Dtype": str(data.dtype),
              "Fill value": data.attrs.get("_FillValue", "N/A"),
              "Time": str(data.coords.get("Time", "N/A").values) if "Time" in data.coords else "N/A"
   }

   separator =  "─" * 63 + '\n'
   spacing = ' ' * ((len(separator) - len(data.name)-2)//2)
   msg =  separator
   msg += f"{spacing} {data.name}\n"
   # msg += f"{'Field':<13} | {'Value'}\n"
   msg += separator
   for key, value in summary.items():
      msg += f" {key:<13} | {value}\n"
   msg += separator
   return msg
