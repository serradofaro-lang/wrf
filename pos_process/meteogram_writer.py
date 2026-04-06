#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import log_help
import logging
LG = logging.getLogger(f'main.{__name__}')
LGp = logging.getLogger(f'perform.{__name__}')

import warnings
warnings.filterwarnings("ignore", message="Converting non-nanosecond precision datetime values to nanosecond precision")

import numpy as np
import wrf
import os
here = os.path.dirname(os.path.realpath(__file__))
HOME = os.getenv('HOME')
import xarray as xr

@log_help.timer(LG, LGp)
def make_meteogram_timestep(WRF,lat,lon):
   # 1D vars
   umet10, vmet10 = WRF.wrf_vars["uvmet10"]  # [y, x]
   umet10_pt = vertical_profile(umet10, lat, lon, WRF)
   vmet10_pt = vertical_profile(vmet10, lat, lon, WRF)

   wspd10 = WRF.wrf_vars["wspd10"]  # [y, x]
   wspd10_pt = vertical_profile(wspd10, lat, lon, WRF)
   # wdir10_pt = vertical_profile(wdir10, lat, lon, WRF)

   t0      = WRF.wrf_vars['t2m']
   t0      = vertical_profile(t0, lat, lon, WRF)
   td0     = WRF.wrf_vars['td2m']
   td0     = vertical_profile(td0, lat, lon, WRF)
   # Rain
   rain = WRF.wrf_vars["rain"]
   rain_pt = vertical_profile(rain, lat, lon, WRF)
   # Clouds
   # low
   low_cloudfrac = WRF.wrf_vars["low_cloudfrac"]
   low_cloudfrac_pt = vertical_profile(low_cloudfrac, lat, lon, WRF)
   # mid
   mid_cloudfrac = WRF.wrf_vars["mid_cloudfrac"]
   mid_cloudfrac_pt = vertical_profile(mid_cloudfrac, lat, lon, WRF)
   # high
   high_cloudfrac = WRF.wrf_vars["high_cloudfrac"]
   high_cloudfrac_pt = vertical_profile(high_cloudfrac, lat, lon, WRF)
   # Terrain
   terrain = vertical_profile(WRF.wrf_vars["terrain"], lat, lon, WRF)
   # DrJack vars (scalars)
   hglider = vertical_profile(WRF.drjack_vars["hglider"], lat, lon, WRF)
   zsfclcl = vertical_profile(WRF.drjack_vars["zsfclcl"], lat, lon, WRF)
   zblcl = vertical_profile(WRF.drjack_vars["zblcl"], lat, lon, WRF)
   wstar = vertical_profile(WRF.drjack_vars["wstar"], lat, lon, WRF)

   # Vertical profile
   umet, vmet = WRF.wrf_vars["uvmet"]
   umet_pt = vertical_profile(umet, lat, lon, WRF)
   vmet_pt = vertical_profile(vmet, lat, lon, WRF)
   tc = vertical_profile(WRF.wrf_vars["tc"], lat, lon, WRF)
   tc = np.array(tc)  # Ensure 1D shape
   rh = vertical_profile(WRF.wrf_vars["rh"], lat, lon, WRF)
   rh = np.array(rh)  # Ensure 1D shape
   p = vertical_profile(WRF.wrf_vars["p"], lat, lon, WRF)
   p = np.array(p)  # Ensure 1D shape
   heights = vertical_profile(WRF.wrf_vars["heights"], lat, lon, WRF)
   heights = np.array(heights)  # Ensure 1D shape

   wspd_pt = np.sqrt(umet_pt**2 + vmet_pt**2)

   # Time info
   timestamp = np.datetime64(WRF.meta['valid_time'],'m')

   ds = xr.Dataset(
       data_vars={
           "terrain_height":     (["time"], [terrain]),
           "rain":               (["time"], [rain_pt]),
           "low_cloudfrac":      (["time"], [low_cloudfrac_pt]),
           "mid_cloudfrac":      (["time"], [mid_cloudfrac_pt]),
           "high_cloudfrac":     (["time"], [high_cloudfrac_pt]),
           "umet10":             (["time"], [umet10_pt]),
           "vmet10":             (["time"], [vmet10_pt]),
           "wspd10":             (["time"], [wspd10_pt]),
           # "wdir10":             (["time"], [wdir10_pt]),
           "t0":                 (["time"], [t0]),
           "td0":                (["time"], [td0]),
           "wstar":              (["time"], [wstar]),
           "hglider":            (["time"], [hglider]),
           "zsfclcl":            (["time"], [zsfclcl]),
           "zblcl":              (["time"], [zblcl]),
           "p":         (["time", "level"], np.atleast_2d(p)),
           "tc":        (["time", "level"], np.atleast_2d(tc)),
           "rh":        (["time", "level"], np.atleast_2d(rh)),
           "heights":   (["time", "level"], np.atleast_2d(heights)),
           "umet":      (["time", "level"], np.atleast_2d(umet_pt)),
           "vmet":      (["time", "level"], np.atleast_2d(vmet_pt)),
           "wspd":      (["time", "level"], np.atleast_2d(wspd_pt)),
       },
       coords={
           "time": [timestamp],
       },
       attrs={
           "location_lat": lat,
           "location_lon": lon,
       }
   )

   return ds


@log_help.timer(LG, LGp)
def append_to_meteogram(ds_new, filepath):
   """
   Appends a new timestep to the meteogram netCDF file using safe context
   management
   """
   # Ensure minute-level time precision for consistency
   ds_new["time"] = ds_new["time"].astype("datetime64[m]")
   units = "minutes since 2007-10-12 00:00:00"
   if not os.path.exists(filepath):
      encoding = {"time": {"units": units, "calendar": "standard"}}
      ds_new.to_netcdf(filepath, mode='w', encoding=encoding)
      ds_combined = ds_new
   else:
      try:
          with xr.open_dataset(filepath) as ds_existing:
             # Ensure consistent time precision
             ds_existing["time"] = ds_existing["time"].astype("datetime64[m]")

             # Ensure we compare with the same type
             times_new = np.array(ds_new["time"].values, dtype="datetime64[m]")

             # Drop overlapping times from existing dataset
             mask = ~np.isin(ds_existing["time"].values.astype("datetime64[m]"), times_new)
             ds_existing_filtered = ds_existing.isel(time=mask)

             # Concatenate and sort
             ds_combined = xr.concat([ds_existing_filtered, ds_new], dim="time", compat="identical", combine_attrs="override")
             ds_combined = ds_combined.sortby("time")

          encoding = {"time": {"units": units, "calendar": "standard"}}
          ds_combined.to_netcdf(filepath, mode='w', encoding=encoding)
          ds_combined.close()
      except Exception as e:
          LG.error(f"Failed to append to meteogram {filepath}: {e}")
          # Return new data only to avoid crash in caller, but file is not updated
          return ds_new
   return ds_combined

def vertical_profile(var, lat, lon, WRF):
   """Interpolates var at given lat/lon from wrf_vars (or drjack_vars)"""
   # Use wrf-python's ll_to_xy, or use nearest neighbor for simplicity
   ncfile = WRF.ncfile
   j,i = wrf.ll_to_xy(ncfile, lat, lon)
   i = i.values
   j = j.values
   # 3D or 2D variable
   if var.ndim == 3:
      return var[:, i, j]
   elif var.ndim == 2:
      return var[i, j]
   else: raise
