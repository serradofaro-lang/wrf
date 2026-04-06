#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import log_help
import logging
LG = logging.getLogger(f'main.{__name__}')
LGp = logging.getLogger(f'perform.{__name__}')

import numpy as np
import datetime as dt
from netCDF4 import Dataset
import wrf
import utils as ut
import drjack_interface as drj
# import mydrjack_num
import os
here = os.path.dirname(os.path.realpath(__file__))
HOME = os.getenv('HOME')
from pathlib import Path
fmt = '%d/%m/%Y-%H:%M'

@log_help.timer(LG, LGp)
def wrfout_info(fname):
   """
   Extract basic metadata and references from a WRF NetCDF file
   Args:
      fname (str or Path): Path to the WRF NetCDF file

   Returns:
      dict: A dictionary containing:
        - ncfile (netCDF4.Dataset): Opened WRF file
        - domain (str): Domain name (d01, d02, etc)
        - bounds (wrf.geo_bounds.GeoBounds): Geographic corners of the domain
        - reflat, reflon (float): Reference lat/lon for Lambert Conformal
        - wrfout_folder (Path): Parent folder of the file
        - date (datetime): Forecast validity time (UTC)
        - GFS_batch (datetime): GFS cycle used for this run
        - creation_date (datetime): File creation/modification timestamp
    """
   fname = Path(fname).resolve()

   # Read WRF data
   try: ncfile = Dataset(fname)
   except Exception as e:
      LG.critical(f"Failed to open WRF file: {fname}")
      raise e

   # Get domain
   DOMAIN = ut.get_domain(fname)
   wrfout_folder = fname.parent  #os.path.dirname(os.path.abspath(fname))
   LG.debug(f'WRFOUT file: {fname}')
   LG.debug(f'WRFOUT folder: {wrfout_folder}')
   LG.debug(f'Domain: {DOMAIN}')
 
   # Report here GFS batch and calculation time
   # gfs_batch = ut.get_GFSbatch(f'{wrfout_folder}/batch.txt')
   try:
       start_date_str = ncfile.getncattr('SIMULATION_START_DATE')
       gfs_batch = dt.datetime.strptime(start_date_str, '%Y-%m-%d_%H:%M:%S')
   except Exception:
       gfs_batch = dt.datetime.now() # Fallback
   
   # LG.info(f'GFS batch: {gfs_batch}')

   # Get Creation date
   creation_date = dt.datetime.fromtimestamp(fname.stat().st_mtime)
   LG.debug(f'Data created: {creation_date.strftime(fmt)}')
 
   # Forecast validity date in UTC from WRF metadata
   try:
      # Fixed: accessing 'Times' directly to avoid pickling issues with wrf.getvar
      times_char = ncfile.variables['Times'][0]
      date_str = "".join([x.decode('utf-8') for x in times_char])
      date = dt.datetime.strptime(date_str, '%Y-%m-%d_%H:%M:%S')
      LG.debug(f'Forecast for: {date}')
   except Exception as e:
      LG.critical(f"Could not parse time from file: {fname}")
      raise e

   # Ref lat/lon
   try:
      reflat = ncfile.getncattr('CEN_LAT')
      reflon = ncfile.getncattr('CEN_LON')
   except AttributeError:
      LG.critical(f"CEN_LAT or CEN_LON not found in {fname}")
      raise
   # bounds contain the bottom-left and upper-right corners of the domain
   # Notice that bounds will not be the left/right/top/bottom-most
   # latitudes/longitudes since the grid is only regular in Lambert Conformal
   bounds = wrf.geo_bounds(wrfin=ncfile)

   LG.debug(f"[{DOMAIN}] File date: {date}, GFS batch: {gfs_batch}")
   LG.debug(f"[{DOMAIN}] Ref lat/lon: {reflat} / {reflon}")

   info = {'ncfile':ncfile,
           'domain': DOMAIN,
           'bounds': bounds,
           'reflat': reflat, 'reflon': reflon,
           'wrfout_folder':wrfout_folder,
           'date': date,
           'GFS_batch': gfs_batch,
           'creation_date': creation_date}
   assert isinstance(info['bounds'], wrf.geobnds.GeoBounds)

   return info

def get_rain(ncfile, prevnc=None):
   """
   Centralized function to extract rain form a provided ncfile
   """
   rainc  = wrf.getvar(ncfile, "RAINC")
   rainnc = wrf.getvar(ncfile, "RAINNC")
   rainsh = wrf.getvar(ncfile, "RAINSH")
   rain = rainc + rainnc + rainsh
   if not prevnc is None:
      rain0 = get_rain(prevnc)
      rain = rain - rain0
      LG.info('Rain is mm in 1 hour')
   else:
      LG.warning('Rain is cumulative')
   return rain

@log_help.timer(LG, LGp)
def wrf_vars(ncfile, prevnc=None, cache={}):
   """
   Extracts meteorological variables from a single WRF output file.

   Parameters:
     wrf_file_path (str): Path to the WRF output NetCDF file.

   Returns:
     dict: A dictionary containing:
      - 'uvmet': Earth-relative wind UV components [m/s], (2, nz, ny, nx)
      - 'w': Vertical wind component (Z) [m/s], (nz, ny, nx)
      - 'uvmet10': Earth-relative wind at 10m [m/s], (2, ny, nx)
      - 'wspd10': Wind speed at 10m [m/s] (ny, nx)
      - 'uvmet{lvl}': UV components of wind at different levels
                      range(1500,3500,500) [m/s] (2, ny, nx)
      - 'theta': Potential temperature [K], (nz, ny, nx)
      - 'tc': Temperature [°C], (nz, ny, nx)
      - 'td': Dewpoint temperature [°C], (nz, ny, nx)
      - 't2m': 2m temperature [K], (ny, nx)
      - 'qvapor': Water vapor mixing ratio [kg/kg], (nz, ny, nx)
      - 'p': Pressure [hPa], (nz, ny, nx)
      - 'rh': Relative humidity [%], (nz, ny, nx) or None if unavailable
      - 'z': Model height AGL [m], (nz, ny, nx)
      - 'bldepth': PBL height [m], (ny, nx)
      - 'hfx': Surface sensible heat flux [W/m²], (ny, nx)
      - 'terrain': Terrain height [m], (ny, nx)
      - 'cape', 'cin', 'lcl', 'lfc': CAPE diagnostics [J/kg or m], (ny, nx)
   """
   getvar = wrf.getvar
   interp = wrf.interplevel

   LG.info("Extracting basic atmospheric variables...")
   heights = getvar(ncfile, "z", cache=cache)      # Model heights AGL (m)
   theta   = getvar(ncfile, "theta", cache=cache)  # Potential temperature
   t       = getvar(ncfile, "tc", cache=cache)     # Temperature (C)
   td      = getvar(ncfile, "td", cache=cache)     # Dewpoint (C)
   t2m     = getvar(ncfile, "T2", cache=cache)     # 2m temperature (K)
   td2     = getvar(ncfile, "td2", cache=cache)    # 2m Dewpoint temperature (C)
   swdown  = getvar(ncfile, "SWDOWN", cache=cache) # Downward short wave flux (W/m^2)
   swdown.values[swdown.values < 1e-5] = 0.0
   qvapor  = getvar(ncfile, "QVAPOR", cache=cache) # Water vapor mixing ratio (kg/kg)
   pmb     = getvar(ncfile, "pressure", cache=cache)  # Full pressure (hPa)
   slp     = getvar(ncfile, "slp", cache=cache)  # Sea Level Pressure (hPa)

   LG.info("Extracting wind variables...")
   # Surface wind
   uvmet10     = getvar(ncfile, "uvmet10", cache=cache)
   wspd10,wdir10 = getvar(ncfile, "uvmet10_wspd_wdir", cache=cache)
   # All heights
   uvmet = getvar(ncfile, "uvmet", cache=cache)   # (2, nz, ny, nx)
   w = getvar(ncfile, "wa", cache=cache)          # Vertical velocity (Z dir)
   wspd,wdir = getvar(ncfile, "uvmet_wspd_wdir", cache=cache)
   # Interpolated wind levels
   wind_levels = list(range(1500, 3500, 500))
   LG.info(f"Interpolating winds to levels: {wind_levels}")
   uvmet_levels = {f"uvmet{lvl}": wrf.interplevel(uvmet, heights, lvl)
                                  for lvl in wind_levels}
   wspd_levels  = {f"wspd{lvl}": wrf.interplevel(wspd, heights, lvl)
                                 for lvl in wind_levels}

   LG.info("Extracting surface and boundary layer data...")
   bldepth = getvar(ncfile, "PBLH", cache=cache)  # PBL depth (m)
   hfx     = getvar(ncfile, "HFX", cache=cache)       # Sensible heat flux
   terrain = getvar(ncfile, "ter", cache=cache)
   lats    = getvar(ncfile, "lat", cache=cache)
   lons    = getvar(ncfile, "lon", cache=cache)

   LG.info("Extracting Rain...")
   rain = get_rain(ncfile, prevnc)

   LG.info("Extracting Cloud frac...")
   low_cloudfrac  = getvar(ncfile, "low_cloudfrac",  cache=cache)
   mid_cloudfrac  = getvar(ncfile, "mid_cloudfrac",  cache=cache)
   high_cloudfrac = getvar(ncfile, "high_cloudfrac", cache=cache)
   blcloudpct = low_cloudfrac + mid_cloudfrac + high_cloudfrac
   blcloudpct = np.clip(blcloudpct*100, None, 100)

   LG.info("Extracting CAPE diagnostics...")
   cape, cin, lcl, lfc = getvar(ncfile, "cape_2d", cache=cache)

   rh = getvar(ncfile, "rh", cache=cache)
   rh2 = getvar(ncfile, "rh2", cache=cache)

   LG.info("Extraction complete.")
   my_vars = {"uvmet": uvmet, "w": w,
              "uvmet10": uvmet10, "wspd10": wspd10,
              **uvmet_levels, **wspd_levels,
              # **{f"uvmet{lvl}": wrf.interplevel(uvmet, heights, lvl) for lvl in wind_levels},
              # **{f"wspd{lvl}": wrf.interplevel(wspd, heights, lvl) for lvl in wind_levels},
              "theta": theta, "tc": t, "td": td, "t2m": t2m, 'td2m':td2,
              "qvapor": qvapor, "rh": rh, "rh2": rh2,
              "hfx": hfx,
              "p": pmb, "slp": slp, 
              "swdown": swdown,
              "heights": heights,
              "bldepth": bldepth,
              "lats": lats, "lons": lons,
              "terrain": terrain,
              "rain": rain,
              "low_cloudfrac": low_cloudfrac,
              "mid_cloudfrac": mid_cloudfrac,
              "high_cloudfrac": high_cloudfrac,
              "blcloudpct": blcloudpct,
              "cape": cape,
              "cin": cin,
              "lcl": lcl,
              "lfc": lfc}
   return my_vars

@log_help.timer(LG, LGp)
def drjack_vars(wrf_vars):
   """
   Computes derived quantities using Dr Jack's functions

   Parameters
   ----------
   u, v: [ndarray] (nz, ny, nx) 3D wind components (x and y) (m/s)
   w: [ndarray] (nz, ny, nx) 3D vertical velocity component (m/s)
   hfx: [ndarray] (ny, nx) 2D surface sensible heat flux (W/m²)
   pressure: [ndarray] (nz, ny, nx) 3D atmospheric full pressure field (hPa)
   heights: [ndarray] (nz, ny, nx) 3D model level heights (m)
   terrain: [ndarray] (ny, nx) 2D terrain height (m)
   bldepth: [ndarray] (ny, nx) 2D boundary layer depth (m)
   tc: [ndarray](nz, ny, nx) 3D temperature (°C)
   td: [ndarray] (nz, ny, nx) 3D dew point temperature (°C)
   qvapor: [ndarray] (nz, ny, nx) 3D water vapor mixing ratio (kg/kg)

   Returns
   -------
   info: [dict] Dictionary containing the following diagnostics:
      - 'wblmaxmin': Maximum up/down-draft in the BL (m/s)
      - 'wstar': Convective velocity scale (m/s)
      - 'hcrit': Critical climb height (m)
      - 'zsfclcl': Surface-based lifted condensation level height (m)
      - 'zblcl': BL-averaged lifted condensation level height (m)
      - 'hglider': Glider-usable thermal height estimate (m)
      - 'ublavgwind', 'vblavgwind': Boundary-layer-averaged wind components (m/s)
      - 'blwind': BL-averaged wind speed (m/s)
      - 'utop', 'vtop': Wind components at BL top (m/s)
      - 'bltopwind': Wind speed at BL top (m/s)

   Notes
   -----
   - Some transpositions are done internally to match Fortran-ordered routines.
   - The `hglider` parameter is computed as the maximum of hcrit and the minimum of
     zsfclcl and zblcl, following DrJack convention.
   """
   # Extracting WRF variables for usability
   u,v      = wrf_vars['uvmet']
   w        = wrf_vars['w']
   hfx      = wrf_vars['hfx']
   pressure = wrf_vars['p']
   heights  = wrf_vars['heights']
   terrain  = wrf_vars['terrain']
   bldepth  = wrf_vars['bldepth']
   tc       = wrf_vars['tc']
   td       = wrf_vars['td']
   qvapor   = wrf_vars['qvapor']

   LG.debug(f"Computing convective variables...")
   wblmaxmin  = drj.calc_wblmaxmin(0, w, heights, terrain, bldepth)
   wstar      = drj.calc_wstar(hfx, bldepth)
   hcrit      = drj.calc_hcrit(wstar, terrain, bldepth, w_crit=0.5) #1.143)

   LG.debug(f"Computing cloud base heights...")
   zsfclcl = drj.calc_sfclclheight(pressure, tc,td, heights,terrain, bldepth)
   zblcl   = drj.calc_blclheight(qvapor,heights,terrain,bldepth,pressure,tc)

   hglider = drj.calc_hglider(hcrit,zsfclcl,zblcl)

   LG.debug(f"Computing wind in the boundary layer...")
   ublavg= drj.calc_wind_blavg(u, heights, terrain, bldepth,
     name='ublavg', description='Boundary-layer-averaged wind U component')
   vblavg= drj.calc_wind_blavg(v, heights, terrain, bldepth,
     name='vblavg', description='Boundary-layer-averaged wind V component')
   uvblavg = np.stack([ublavg, vblavg], axis=0)
   blwind = drj.calc_Wspeed(ublavg, vblavg, name='blwind',
                              description='Boundary-layer-averaged wind speed')

   LG.debug(f"Computing wind at BL top...")
   utop, vtop = drj.calc_bltopwind(u, v, heights, terrain, bldepth)
   uvtop = np.stack([utop, vtop], axis=0)
   bltopwind = drj.calc_Wspeed(utop, vtop, name='bltopwind',
                              description='Boundary-layer-averaged wind speed')

   info = {'wblmaxmin': wblmaxmin,
           'wstar': wstar,
           'hcrit': hcrit,
           'zsfclcl': zsfclcl,
           'zblcl': zblcl,
           'hglider': hglider,
           'uvblavg': uvblavg,  #ublavg, 'vblavg': vblavg,
           'blwind': blwind,
           'uvtop': uvtop, #utop, 'vtop': vtop,
           'bltopwind': bltopwind}
   return info
