import folium
import pandas as pd
import os
import re
import sys
from pathlib import Path

import folium
import pandas as pd
import os
import re
import sys
import configparser
from pathlib import Path

# Add pos_process to path for utils (optional, keeping for backward compatibility if needed)
sys.path.append("/home/zalo/meteo/pos_process")

# Determine config file path
if len(sys.argv) > 1:
    CONFIG_FILE = sys.argv[1]
else:
    CONFIG_FILE = 'config.ini'

print(f"Using config file: {CONFIG_FILE}")

if not os.path.exists(CONFIG_FILE):
    print(f"Error: Config file not found at {CONFIG_FILE}")
    sys.exit(1)

# Load config using configparser to handle interpolation
config = configparser.ConfigParser(interpolation=configparser.ExtendedInterpolation())
config.read(CONFIG_FILE)

# Constants derived from config
METEO_ROOT = str(Path(CONFIG_FILE).parent)
try:
    # Try to get paths from config, fallback to defaults relative to METEO_ROOT
    if 'paths' in config and 'configs' in config['paths']:
         CONFIGS_DIR = config['paths']['configs']
    else:
         CONFIGS_DIR = os.path.join(METEO_ROOT, 'configs')
         
    # Resolve relative paths if necessary
    if not os.path.isabs(CONFIGS_DIR):
        CONFIGS_DIR = os.path.join(METEO_ROOT, CONFIGS_DIR)
        
except Exception as e:
    print(f"Warning parsing config: {e}. Using default configs dir.")
    CONFIGS_DIR = os.path.join(METEO_ROOT, 'configs')

NAMELIST_WPS = os.path.join(METEO_ROOT, 'namelist.wps')
OUTPUT_MAP = os.path.join(METEO_ROOT, 'config_verification_map.html')

def parse_namelist(filepath):
    """
    Simulated parsing of namelist.wps for domain info.
    """
    if not os.path.exists(filepath):
        # Fallback to pre_process if not in root
        filepath = os.path.join(METEO_ROOT, 'pre_process', 'WPS', 'namelist.wps')
        
    with open(filepath, 'r') as f:
        content = f.read()

    ref_lat = float(re.search(r'ref_lat\s*=\s*([\d\.]+)', content).group(1))
    ref_lon = float(re.search(r'ref_lon\s*=\s*([\d\.\-]+)', content).group(1))
    
    # Simple extraction of max_dom
    max_dom = int(re.search(r'max_dom\s*=\s*(\d+)', content).group(1))
    
    return {'ref_lat': ref_lat, 'ref_lon': ref_lon, 'max_dom': max_dom, 'path': filepath}

def parse_zooms(filepath):
    import configparser
    config = configparser.ConfigParser()
    config.read(filepath)
    zooms = {}
    for section in config.sections():
        zooms[section] = {
            'left': config.getfloat(section, 'left'),
            'right': config.getfloat(section, 'right'),
            'bottom': config.getfloat(section, 'bottom'),
            'top': config.getfloat(section, 'top'),
            'parent': config.get(section, 'parent', fallback='unknown')
        }
    return zooms

def add_csv_markers(map_obj, filepath, color, icon_name='info-sign', zooms=None):
    try:
        # We try to read without header first
        df = pd.read_csv(filepath, header=None)
        
        # Heuristic to check if first row is header
        if isinstance(df.iloc[0,0], str) and not df.iloc[0,0].replace('.','',1).isdigit():
             df = pd.read_csv(filepath) # Reload with header
        else:
             # Assign default names
             if len(df.columns) >= 3:
                 df.columns = ['lat', 'lon', 'name'] + [f'col_{i}' for i in range(3, len(df.columns))]
             elif len(df.columns) == 2:
                 df.columns = ['lat', 'lon']
                 df['name'] = 'Unnamed'

        group = folium.FeatureGroup(name=os.path.basename(filepath))
        
        is_stations_file = 'stations' in os.path.basename(filepath)
        
        for _, row in df.iterrows():
            try:
                lat = float(row['lat'])
                lon = float(row['lon'])
                name = str(row['name']) if 'name' in df.columns else os.path.basename(filepath)
                
                # Default style
                current_color = color
                current_icon = icon_name
                popup_msg = f"<b>{name}</b><br>{os.path.basename(filepath)}"
                
                # Check bounds if it's a stations file and zooms are provided
                if is_stations_file and zooms:
                    is_inside = False
                    inside_zooms = []
                    for z_name, z in zooms.items():
                        if (z['bottom'] <= lat <= z['top']) and (z['left'] <= lon <= z['right']):
                            is_inside = True
                            inside_zooms.append(z_name)
                    
                    if not is_inside:
                        current_color = 'red'
                        current_icon = 'exclamation-sign'
                        popup_msg += "<br><span style='color:red'><b>WARNING: Outside all zooms!</b></span>"
                        print(f"WARNING: Station '{name}' ({lat}, {lon}) is OUTSIDE all defined zooms.")
                    else:
                        popup_msg += f"<br>Inside: {', '.join(inside_zooms)}"
                
                folium.Marker(
                    [lat, lon],
                    popup=popup_msg,
                    icon=folium.Icon(color=current_color, icon=current_icon)
                ).add_to(group)
            except ValueError:
                continue # Skip bad rows
        
        group.add_to(map_obj)
        print(f"Added {len(df)} markers from {os.path.basename(filepath)}")
        
    except Exception as e:
        print(f"Error processing {filepath}: {e}")

def main():
    print(f"Reading configuration from {CONFIG_FILE}")
    
    # 1. Setup Map
    namelist_info = parse_namelist(NAMELIST_WPS)
    print(f"Namelist Info (from {namelist_info['path']}): {namelist_info}")
    
    m = folium.Map(location=[namelist_info['ref_lat'], namelist_info['ref_lon']], zoom_start=8)
    
    # 2. Add Domain Center (Reference)
    folium.Marker(
        [namelist_info['ref_lat'], namelist_info['ref_lon']],
        popup="Namelist Reference Center",
        icon=folium.Icon(color='red', icon='star')
    ).add_to(m)

    # 3. Add Zooms
    zooms_path = os.path.join(CONFIGS_DIR, 'zooms.ini')
    zooms = {}
    if os.path.exists(zooms_path):
        zooms = parse_zooms(zooms_path)
        print(f"Found {len(zooms)} zoom regions")
        for name, z in zooms.items():
            bounds = [[z['bottom'], z['left']], [z['top'], z['right']]]
            folium.Rectangle(
                bounds=bounds,
                color='blue',
                fill=True,
                fill_opacity=0.1,
                popup=f"Zoom: {name} ({z.get('parent')})"
            ).add_to(m)
    
    # 4. Add Domain Bounds (from config.ini)
    try:
        import configparser
        config = configparser.ConfigParser()
        config.read(CONFIG_FILE)
        if 'domain_bounds' in config:
            left = config.getfloat('domain_bounds', 'left_lon')
            right = config.getfloat('domain_bounds', 'right_lon')
            top = config.getfloat('domain_bounds', 'top_lat')
            bottom = config.getfloat('domain_bounds', 'bottom_lat')
            
            bounds_group = folium.FeatureGroup(name="Domain Bounds (config.ini)")
            bounds = [[bottom, left], [top, right]]
            folium.Rectangle(
                bounds=bounds,
                color='red',
                weight=2,
                fill=True,
                fill_opacity=0.05,
                popup="Domain Bounds (config.ini)"
            ).add_to(bounds_group)
            bounds_group.add_to(m)
            print("Added domain_bounds layer from config.ini")
    except Exception as e:
        print(f"Error adding domain_bounds layer: {e}")

    # 5. Add CSVs
    # Define colors mapping for different file types
    csv_files = {
        'cities.csv': 'orange',
        'peaks.csv': 'gray',
        'takeoffs.csv': 'green',
        'soundings_d01.csv': 'purple',
        'soundings_d02.csv': 'darkpurple',
        'stations_d01.csv': 'darkblue',
        'stations_d02.csv': 'cadetblue'
    }
    
    for filename, color in csv_files.items():
        filepath = os.path.join(CONFIGS_DIR, filename)
        if os.path.exists(filepath):
            add_csv_markers(m, filepath, color, zooms=zooms)
        else:
            print(f"Warning: File not found: {filepath}")

    # Add layer control
    folium.LayerControl().add_to(m)
    
    # Save
    m.save(OUTPUT_MAP)
    print(f"Map generated at: {OUTPUT_MAP}")

if __name__ == "__main__":
    main()
