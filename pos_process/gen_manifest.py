#!/usr/bin/python3
# -*- coding: UTF-8 -*-

"""
gen_manifest.py

Scans the WRF PLOTS directory and generates a manifest.json file.
This JSON serves as the database for the static web viewer.
"""

import sys
import os
import json
import logging
from pathlib import Path
from datetime import datetime
import csv
from configparser import ConfigParser, ExtendedInterpolation

# Setup basic logging
logging.basicConfig(level=logging.WARNING, format='%(asctime)s - %(levelname)s - %(message)s', stream=sys.stdout)
LG = logging.getLogger(__name__)

# Load config using utils
sys.path.append(os.path.dirname(os.path.realpath(__file__)))
try:
    import utils as ut
except ImportError as e:
    LG.critical(f"Failed to import utils: {e}")
    sys.exit(1)

def load_ini_sections(ini_path):
    """Loads all sections from an INI file."""
    config = ConfigParser(interpolation=ExtendedInterpolation())
    config.read(ini_path)
    return config

def get_variable_metadata(ini_path):
    """
    Extracts variable metadata (Title, Units, ID) directly from plots.ini.
    Returns a list of dicts: [{'id': 't2m', 'title': 'Temperatura', 'units': '°C'}, ...]
    """
    if not ini_path or not os.path.exists(ini_path):
        return []

    config = load_ini_sections(ini_path)
    vars_list = []
    
    for section in config.sections():
        # Clean naming: strip suffixes if any (though plots.ini usually has clean keys)
        # We use the section name as the ID
        
        entry = {
            "id": section,
            "title": config[section].get("title", section),
            "units": config[section].get("units", ""),
            "type": config[section].get("tipo", "unknown")
        }
        vars_list.append(entry)
    
    return vars_list

def get_zooms_config(ini_path):
    """
    Parses zooms.ini to get defined zooms per domain.
    Returns a dictionary: {'d01': [], 'd02': ['Interior', 'Costa', ...]}
    """
    if not ini_path or not os.path.exists(ini_path):
        return {}
    
    config = load_ini_sections(ini_path)
    zooms_by_domain = {}
    
    for section in config.sections():
        parent = config[section].get("parent", "unknown")
        if parent not in zooms_by_domain:
            zooms_by_domain[parent] = []
        zooms_by_domain[parent].append(section)
        
    return zooms_by_domain

def get_soundings_config(configs_folder):
    """
    Parses soundings_d0*.csv files in the configs folder.
    Returns a dictionary: {'d01': ['St1', 'St2'], 'd02': [...]}
    """
    soundings_by_domain = {}
    
    try:
        # We scan for soundings_d01.csv, soundings_d02.csv, etc.
        # configs_folder is a Path object
        for f in configs_folder.glob("soundings_d0*.csv"):
            # Extract domain from filename: soundings_d01.csv -> d01
            domain = f.stem.split('_')[-1] # d01
            
            stations = []
            if f.stat().st_size > 0:
                try:
                    with open(f, 'r') as csvfile:
                        reader = csv.reader(csvfile)
                        for row in reader:
                            if not row: continue
                            # Expected format: Lat, Lon, Name (3 cols)
                            if len(row) >= 3:
                                name = row[2].strip()
                                st_id = name.lower().replace(' ', '_')
                                if st_id:
                                    stations.append({"id": st_id, "name": name})
                except Exception as e:
                    LG.warning(f"Error reading soundings csv {f}: {e}")
            
            soundings_by_domain[domain] = stations
            
    except Exception as e:
        LG.warning(f"Error scanning for soundings config: {e}")
        
    return soundings_by_domain

def scan_availability(base_dir, start_hour=0, end_hour=23):
    """
    Scans the directory for available domains, dates and hours.
    Returns a dict with domains, dataset_dates (latest/archive) and hours (by date).
    """
    base_path = Path(base_dir)
    availability = {
        "domains": [],
        "dataset_dates": {
            "latest": [],
            "archive": []
        },
        "hours": {} # { "YYYY-MM-DD": [0, 1, 2, ... 23] }
    }
    
    if not base_path.exists():
        LG.error(f"Base plot directory not found: {base_path}")
        return availability

    # 1. Find Domains (d01, d02...)
    domain_dirs = sorted(list(base_path.glob("d0*")))
    availability["domains"] = [d.name for d in domain_dirs if d.is_dir()]
    
    # 2. Find Dates and Hours
    all_dates = set()
    date_hours = {} # Map date -> set(hours)
    
    for d_path in domain_dirs:
        # Expected structure: Domain/YYYYMMDD
        day_dirs = d_path.glob("*")
        for day_dir in day_dirs:
            if not day_dir.is_dir(): continue
            try:
                # Parse YYYYMMDD format
                date_dirname = day_dir.name
                if len(date_dirname) != 8 or not date_dirname.isdigit():
                    continue
                
                yyyy = date_dirname[:4]
                mm = date_dirname[4:6]
                dd = date_dirname[6:8]
                date_str = f"{yyyy}-{mm}-{dd}"
                # Validate date
                datetime(int(yyyy), int(mm), int(dd))
                all_dates.add(date_str)
                
                # Scan files for hours: HHMM_*.webp
                if date_str not in date_hours:
                    date_hours[date_str] = set()
                
                for f in day_dir.glob("*.webp"):
                    # Filename format: HHMM_variable...
                    try:
                        hh = int(f.name[:2])
                        mm_val = int(f.name[2:4]) # avoid shadowing mm
                        if start_hour <= hh <= end_hour:
                             date_hours[date_str].add(hh)
                    except:
                        pass
            except:
                continue
                
    # Categorize Dates
    today_str = datetime.now().strftime("%Y-%m-%d")
    today_dt = datetime.strptime(today_str, "%Y-%m-%d")
    
    sorted_dates = sorted(list(all_dates), reverse=True)
    
    latest_dates = []
    archive_dates = []
    
    for d_str in sorted_dates:
        try:
            d_dt = datetime.strptime(d_str, "%Y-%m-%d")
            # Compare dates only
            if d_dt.date() >= today_dt.date():
                latest_dates.append(d_str)
            else:
                archive_dates.append(d_str)
        except:
             pass

    # Limit archive to 2 most recent days
    archive_dates = archive_dates[:2]
    
    availability["dataset_dates"]["latest"] = latest_dates
    availability["dataset_dates"]["archive"] = archive_dates
    
    # Populate hours only for kept dates
    kept_dates = latest_dates + archive_dates
    for d_str in kept_dates:
        availability["hours"][d_str] = sorted(list(date_hours.get(d_str, [])))
             
    return availability

def build_manifest(base_dir, config_data, start_hour=0, end_hour=23):
    """
    Builds the complete manifest using scanned availability and provided configuration.
    """
    availability = scan_availability(base_dir, start_hour, end_hour)
    
    # Construct final manifest
    manifest = {
        "configuration": config_data,
        "domains": availability["domains"],
        "dataset_dates": availability["dataset_dates"],
        "hours": availability["hours"],
        "last_updated": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    }
    
    return manifest

def get_csv_locations(csv_path):
    """
    Reads a CSV file containing locations (Lat, Lon, Name).
    Returns a list of dicts: [{'name': '...', 'lat': ..., 'lon': ...}]
    """
    locations = []
    if not csv_path.exists():
        LG.warning(f"CSV file not found: {csv_path}")
        return locations

    try:
        with open(csv_path, 'r') as f:
            reader = csv.reader(f)
            for row in reader:
                if not row: continue
                # Expected: Lat, Lon, Name
                if len(row) >= 3:
                    try:
                        lat = float(row[0])
                        lon = float(row[1])
                        name = row[2].strip()
                        locations.append({"name": name, "lat": lat, "lon": lon})
                    except ValueError:
                        LG.warning(f"Invalid coordinate in {csv_path}: {row}")
    except Exception as e:
        LG.error(f"Error reading {csv_path}: {e}")
        
    return locations

import argparse

def main():
    try:
        parser = argparse.ArgumentParser(description="Generate manifest for WRF outputs.")
        parser.add_argument("--config", "-c", type=str, help="Path to config.ini file")
        # Parse known args to allow running with positional argument as well for backward compatibility
        args, unknown = parser.parse_known_args()
        
        if args.config:
            conf_path = Path(args.config).resolve()
        elif unknown:
            # Maybe passed as a direct string like: python gen_manifest.py /path/to/config.ini
            # We assume it's the first unknown param that doesn't start with --
            conf_path = Path(unknown[0]).resolve()
        else:
            here = Path(__file__).parent.resolve()
            # Intentar buscar config.ini en el directorio padre (root del proyecto)
            conf_path = here.parent / "config.ini"
            if not conf_path.exists():
                # Fallback al directorio actual (comportamiento antiguo)
                conf_path = here / "config.ini"
                
        if not conf_path.exists():
            LG.error(f"Config file not found: {conf_path}")
            sys.exit(1)
        
        # 1. Load Paths
        paths = ut.load_config_or_die(conf_path)
        
        plots_folder = paths.get('plots_folder')
        configs_folder = paths.get('configs_folder')
        
        if not plots_folder or not configs_folder:
            LG.error("Missing plots_folder or configs in config.ini")
            sys.exit(1)
            
        plots_folder = Path(os.path.expandvars(plots_folder))
        configs_folder = Path(os.path.expandvars(configs_folder))
        
        plots_ini_path = configs_folder / "plots.ini"
        zooms_ini_path = configs_folder / "zooms.ini"
        cities_path = configs_folder / "cities.csv"
        peaks_path = configs_folder / "peaks.csv"
        takeoffs_path = configs_folder / "takeoffs.csv"

        # 2. Parse Configs
        all_vars = get_variable_metadata(plots_ini_path)
        variables = [v for v in all_vars if v.get('type') == 'plot']
        layers = [v for v in all_vars if v.get('type') == 'capa']

        config_data = {
            "variables": variables,
            "layers": layers,
            "zooms": get_zooms_config(zooms_ini_path),
            "soundings": get_soundings_config(configs_folder) if configs_folder else {},
            "cities": get_csv_locations(cities_path),
            "peaks": get_csv_locations(peaks_path),
            "takeoffs": get_csv_locations(takeoffs_path)
        }

        # LG.info(f"Loaded {len(config_data['variables'])} variables from config.")
        # LG.info(f"Loaded zooms: {list(config_data['zooms'].keys())}")
        # LG.info(f"Loaded {len(config_data['cities'])} cities, {len(config_data['peaks'])} peaks, {len(config_data['takeoffs'])} takeoffs.")

        # Read domain, web_viewer_dir and schedule from config
        c_tmp = ConfigParser(interpolation=ExtendedInterpolation())
        c_tmp.read(conf_path)
        domain = c_tmp['paths']['domain']
        
        start_hour = c_tmp.getint('schedule', 'start_hour', fallback=0) if 'schedule' in c_tmp else 0
        end_hour = c_tmp.getint('schedule', 'end_hour', fallback=23) if 'schedule' in c_tmp else 23
        
        web_viewer_dir = c_tmp['paths'].get('web_viewer_dir')
        if web_viewer_dir:
            web_dir = Path(os.path.expandvars(web_viewer_dir))
        else:
            # Fallback
            web_dir = configs_folder.parent.parent / "web_viewer"

        # 3. Build Manifest
        # Determine Search Root
        target_dir = Path(plots_folder)
        search_root = target_dir
        
        LG.info(f"Buscando gráficos en {search_root}...")
        
        if not search_root.exists():
            LG.error(f"Plots folder does not exist: {search_root}")
             
        manifest = build_manifest(search_root, config_data, start_hour, end_hour)

        # Output
        web_dir.mkdir(parents=True, exist_ok=True)
        output_file = web_dir / "manifest.json"

        # Relative path logic:
        # If plots_folder is /.../PLOTS/Galicia, base_path should be PLOTS/Galicia
        # This assumes the web server serves the parent of PLOTS as root, or handles the symlink correctly.
        # But wait, run_server.sh links `inputs/PLOTS` -> `.../PLOTS`.
        # So we probably want `PLOTS/<domain>`.
        
        # Let's derive it from plots_folder relative to its parent's parent if standard structure,
        # OR just use the folder name and its parent.
        
        # Actually simplest is: use the last two parts of the path? 
        # e.g. /home/zalo/meteo/PLOTS/Galicia -> PLOTS/Galicia
        
        p = Path(plots_folder)
        if len(p.parts) >= 2:
            base_path = f"{p.parent.name}/{p.name}" 
        else:
            base_path = f"PLOTS/{domain}" # Fallback
            
        manifest["base_path"] = base_path

        with open(output_file, 'w') as f:
            json.dump(manifest, f, indent=2)
            
        LG.info(f"Manifiesto generado en {output_file}")
        # Calculate total dates
        n_dates = len(manifest['dataset_dates']['latest']) + len(manifest['dataset_dates']['archive'])
        # LG.info(f"Found {n_dates} days.")
        


    except Exception as e:
        LG.error(f"Fallo al generar el manifiesto: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
