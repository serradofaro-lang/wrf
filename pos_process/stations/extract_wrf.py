#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import log_help
import logging
LG = logging.getLogger(f'main.{__name__}')
LGp = logging.getLogger(f'perform.{__name__}')

import wrf
import pandas as pd
from pathlib import Path
from . import schema 
from . import utils as ut


# STANDARD_COLUMNS = ["timestamp", "station_id", "lat", "lon",
#                     "wind_speed", "wind_dir", "temperature", "rh", "pressure"]

@log_help.timer(LG, LGp)
def save_prediction(WRF, station_id, lat_req, lon_req, folder):
   """
   Extract WRF-predicted data at the closest grid point to a station location
   and append/update the station's daily prediction CSV

   Parameters:
      - WRF (CalcData): CalcData object already loaded
      - station_id (str): Station identifier (used in filename)
      - lat_req, lon_req (float): Station lat/lon
      - folder (Path or str): Base folder to save predictions
   """
   ncfile = WRF.ncfile
   date = WRF.meta["valid_time"]
   output_folder = Path(folder).expanduser()
   output_folder.mkdir(parents=True, exist_ok=True)

   csv_path = output_folder / f"{station_id}.csv"

   # Get closest model point
   j, i = wrf.ll_to_xy(ncfile, lat_req, lon_req)
   
   # Check if point is within domain bounds
   # wrf.ll_to_xy returns numpy ints or xarray objects, ensure we compare properly
   # Dimensions are typically (south_north, west_east) for 2D fields
   lats = wrf.getvar(ncfile, "lat")
   lons = wrf.getvar(ncfile, "lon")
   
   ny, nx = lats.shape
   if not (0 <= i < ny and 0 <= j < nx):
      LG.warning(f"Station {station_id} at ({lat_req}, {lon_req}) is out of domain bounds (i={i}, j={j}, shape={lats.shape}). Skipping.")
      return

   lat_model = lats[i, j].values
   lon_model = lons[i, j].values

   # Extract relevant data
   # Temperature
   swdown     = WRF.wrf_vars['swdown'] # (W/m^2)
   swdown_val = swdown[i, j].values
   # Temperature
   t2m     = WRF.wrf_vars['t2m']       # (K)
   t2m_val = t2m[i, j].values - 273.15 # (C)
   # Relative humidity
   rh     = WRF.wrf_vars['rh2'] # (%)
   rh_val = rh[i, j].values
   # Pressure
   p     = WRF.wrf_vars["slp"]  # (hPa)
   p_val = p[i, j].values
   # Wind
   wspd10, wdir10 = wrf.getvar(ncfile, 'uvmet10_wspd_wdir')
   wspd10 = wspd10 * 3.6  # m/s → km/h
   wspd_val = wspd10[i, j].values
   wdir_val = wdir10[i, j].values

   # Create single-row DataFrame

   row = dict.fromkeys( schema.STATION_CSV_COLUMNS )  # ensures all keys present
   row = {
       "time": date.replace(tzinfo=None),
       # "station_id": station_id,
       # "lat": lat_model,
       # "lon": lon_model,
       "wind_speed_avg": wspd_val,
       "wind_heading": wdir_val,
       "temperature": t2m_val,
       "rh": rh_val,
       "pressure": p_val,
       "swdown": swdown_val,
   }
   new_df = pd.DataFrame([row])
   new_df = ut.reconcile_station_dataframe(new_df)


   # Append/update existing CSV
   if csv_path.exists():
      LG.info(f"File {csv_path} already exists")
      df = ut.read_station_csv(csv_path)
      # remove existing row for this time
      df = df.drop(index=df.index.intersection(new_df.index), errors='ignore')
      df = pd.concat([df, new_df]).sort_index()
   else:
      LG.info(f"File {csv_path} does not exist")
      df = new_df

   LG.info(f'Saving station {station_id} to file {csv_path}')
   ut.save_station_csv(df, csv_path)
