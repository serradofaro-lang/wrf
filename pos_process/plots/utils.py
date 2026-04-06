#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import os
import log_help
import logging
LG = logging.getLogger(f'main.{__name__}')
LGp = logging.getLogger(f'perform.{__name__}')

import matplotlib as mpl
mpl.use('Agg')

import datetime as dt
from configparser import ConfigParser, ExtendedInterpolation
import matplotlib.pyplot as plt
from typing import Union, Optional, Tuple, List


def utc_shift():
   UTCshift = dt.datetime.now() - dt.datetime.utcnow()
   UTCshift = dt.timedelta(hours = round(UTCshift.total_seconds()/3600))
   LG.info(f'UTCshift: {UTCshift}')
   return UTCshift


@log_help.timer(LG, LGp)
def save_figure(thisax,fname, dpi=100, ext='webp'):
   LG.debug(f'Saving: {fname}.{ext}')
   thisfig = thisax.figure
   thisfig.savefig(f"{fname}.{ext}", format=ext, dpi=dpi, transparent=True,
            bbox_inches='tight', pad_inches=0)
   LG.info(f'Saved: {fname}.{ext}')
   # plt.close('all')


@log_help.timer(LG, LGp)
def save_zooms(myax, crs_data, zooms, out_dir, base_name, save_func):
    """
    Save zoomed-in views of a plot by adjusting the map extent.

    Parameters
    ----------
    ax : cartopy.mpl.geoaxes.GeoAxes
        The plot axis to zoom and save.
    crs_data : cartopy.crs.CRS
        The CRS of the data (typically PlateCarree).
    zooms : dict
        Dictionary of {zoom_name: (left, right, bottom, top)}.
    out_dir : Path
        Output directory to save the images.
    base_name : str
        Base filename (e.g. 'terrain', 'temperature').
    save_func : callable
        Function to save the figure. Typically `save_figure(ax, fname)`.
    """
    for name, bounds in zooms.items():
        myax.set_extent(bounds, crs=crs_data)
        fname = out_dir / f"{base_name}_z{name}"
        save_func(myax, fname)
        LG.info(f"Saved zoom: {name}")


def load_config(fname='plots.ini'):
   """
   Load and parse a plotting configuration INI file.
   This is intended for use with property-based plotting definitions, such as
   scalar field settings for WRF output.
   Parameters
   ----------
   fname : [str] Path to the INI file containing plotting configuration.

   Returns
   -------
   dict Dictionary where each key is a section (e.g., 'wstar', 'cape') and the 
        value is a dictionary of parsed parameters, with numeric fields cast
        to float when appropriate.
   """
   if not os.path.isfile(fname):
       LG.critical(f"Config file not found: {fname}")
       raise FileNotFoundError(f"Configuration file not found: {fname}")

   LG.info(f"Loading plotting configuration from: {fname}")
   config = ConfigParser(inline_comment_prefixes='#')
   config._interpolation = ExtendedInterpolation()
   config.read(fname)

   parsed = {}
   for section in config.sections():
       parsed[section] = {}
       for key, val in config[section].items():
           # Auto-convert numeric fields when expected
           if key in {"factor", "delta", "vmin", "vmax"}:
               try:
                   parsed[section][key] = float(val)
               except ValueError:
                   LG.warning(f"Failed to convert {key}='{val}' to float in section [{section}]")
                   parsed[section][key] = val  # fallback to raw string
           else:
               parsed[section][key] = val

   return parsed


@log_help.timer(LG, LGp)
def scalar_props(config: Union[str, dict], section: str) -> Tuple[float, float, float, float, Optional[List[float]], str, str, str]:
    """
    Retrieve scalar field plotting configuration for a given property.

    Parameters
    ----------
    config : str or dict
        Path to .ini file or pre-parsed config dictionary from load_config().
    section : str
        The section/property name (e.g. "wstar", "rain").

    Returns
    -------
    tuple
        (factor, vmin, vmax, delta, levels, cmap, units, title)

    Raises
    ------
    KeyError
        If any required field is missing.
    ValueError
        If any required field cannot be converted to float.
    """
    if isinstance(config, str):
        if not os.path.isfile(config):
            LG.critical(f"Config file not found: {config}")
            raise FileNotFoundError(f"Config file not found: {config}")
        LG.info(f"Loading config file: {config} for section [{section}]")
        parser = ConfigParser(inline_comment_prefixes='#')
        parser._interpolation = ExtendedInterpolation()
        parser.read(config)
        if section not in parser:
            raise KeyError(f"Section [{section}] not found in config file.")
        cfg = parser[section]
    else:
        LG.info(f"Using preloaded config for section [{section}]")
        if section not in config:
            raise KeyError(f"Section [{section}] not found in config dict.")
        cfg = config[section]

    # Required numeric fields
    required_keys = ['factor', 'vmin', 'vmax', 'delta']
    missing = [k for k in required_keys if k not in cfg]
    if missing:
        raise KeyError(f"Missing required keys in [{section}]: {', '.join(missing)}")

    try:
        factor = float(cfg['factor'])
        vmin   = float(cfg['vmin'])
        vmax   = float(cfg['vmax'])
        delta  = float(cfg['delta'])
    except ValueError as e:
        raise ValueError(f"Non-numeric value in [{section}]: {e}")

    # Optional levels
    levels = cfg.get('levels', [])  
    if isinstance(levels, str):
       if levels.lower() in ['false', 'none', '']:
           levels = []
       else:
           levels = levels.replace(']','').replace('[','')
           levels = list(map(float,levels.split(',')))
    elif isinstance(levels, list):
       LG.debug(f"Levels not provided for {section}. Calculate them with vmin, vmax, delta")
    else:
       LG.critical(f"Error parsing levels for {section}")
       levels = []
    # if levels == False: levels = None
    # elif levels != None:
    #    levels = levels.replace(']','').replace('[','')
    #    levels = list(map(float,levels.split(',')))
    #    levels = [float(l) for l in levels]
    # else: levels = []

    # if raw_levels:
    #     try:
    #         raw_levels = raw_levels.strip().lstrip("[").rstrip("]")
    #         levels = [float(x) for x in raw_levels.split(',') if x.strip()]
    #     except Exception as e:
    #         LG.warning(f"Could not parse levels in [{section}]: {e}")
    #         levels = None

    # Optional metadata
    cmap  = cfg.get('cmap', 'viridis')
    units = cfg.get('units', '')
    title = cfg.get('title', section)

    return factor, vmin, vmax, delta, levels, cmap, units, title

