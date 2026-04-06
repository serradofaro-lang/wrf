#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import log_help
import logging
LG = logging.getLogger(f'main.{__name__}')
LGp = logging.getLogger(f'perform.{__name__}')

import sys
import numpy as np
import pandas as pd
from pathlib import Path
from stations.schema import STATION_CSV_COLUMNS
from playwright.sync_api import sync_playwright
import requests
import time

# OpenWeatherMap API Key (hardcoded as per instructions)
APPID = "46b20b0407a41f2b8d6095ee5636b275"


def make_request(url: str, element: str = None) -> str:
   t_out = 15000
   with sync_playwright() as p:
      browser = p.chromium.launch(headless=True, args=["--disable-gpu", "--no-sandbox"])
      context = browser.new_context()
      try:
         page = browser.new_page()
         page.goto(url, timeout=t_out)  # 15 seconds
         # Wait for a specific element if provided
         if element:
            page.wait_for_selector(element, timeout=t_out)
         return page.content()
      finally:
         context.close()
         browser.close()


def validate_station_df(df):
   """
   Check that the provided DataFrame contains all the requested columns
   Added an exception in case 'time' was passed as index instead of column
   """
   if df.index.name == 'time':
      req_columns = [c for c in STATION_CSV_COLUMNS if c !='time']
      # LG.warning('time column was passed as index')
   else: req_columns = STATION_CSV_COLUMNS
   missing = set(req_columns) - set(df.columns)
   if missing:
      raise ValueError(f"Missing columns in station CSV: {missing}")
   else: return True


def save_station_csv(df, csv_path):
   """
   Save a cleaned station DataFrame to CSV. Overwrites existing file.

   Args:
       df (pd.DataFrame): DataFrame to save
       csv_path (Path or str): Output path
   """
   try:
      if validate_station_df(df):
         # Check if file exists to append/merge
         csv_path = Path(csv_path)
         if csv_path.exists():
             try:
                 existing_df = pd.read_csv(csv_path, parse_dates=['time'])
                 # Ensure existing df has 'time' as column for concatenation or check index
                 if existing_df.index.name == 'time':
                     existing_df.reset_index(inplace=True)
                 
                 # Prepare new df
                 if df.index.name == 'time':
                     df_to_merge = df.reset_index()
                 else:
                     df_to_merge = df
                 
                 # Concatenate
                 combined_df = pd.concat([existing_df, df_to_merge], ignore_index=True)
                 
                 # Deduplicate based on time
                 combined_df.drop_duplicates(subset=['time'], keep='last', inplace=True)
                 
                 # Set index back to time for saving/sorting logic consistency if needed, 
                 # but validate_station_df checks columns.
                 # Let's stick to the previous pattern: 'time' is a column in the saved file?
                 # read_station_csv sets index to time.
                 # save_station_csv expects df to have time column or index? 
                 # validate_station_df checks if 'time' is index or column.
                 
                 df = combined_df
             except Exception as load_err:
                 LG.warning(f"Could not merge with existing file {csv_path}, overwriting. Error: {load_err}")

         if df.index.name == 'time':
             df = df.reset_index()

         df.sort_values("time", inplace=True)
         df.set_index('time', inplace=True)
         df.round(5).to_csv(csv_path)
         LG.info(f"Saved station data to {csv_path}")
      else: LG.critical('DataFrame not valid')
   except Exception as e:
      LG.critical(f"Failed to save {csv_path}: {e}")
      raise


def read_station_csv(csv_path):
   """
   Load a station CSV file, validate its structure and types.

   Args:
       csv_path (str or Path): Path to CSV file.

   Returns:
       pd.DataFrame: Cleaned and validated DataFrame.

   Raises:
       FileNotFoundError: If file doesn't exist.
       ValueError: If required columns are missing or malformed.
   """
   csv_path = Path(csv_path)
   if not csv_path.is_file():
      raise FileNotFoundError(f"Station CSV not found: {csv_path}")

   try: 
      df = pd.read_csv(csv_path, parse_dates=["time"])
      df.set_index('time', inplace=True)
      
      # Parse optional date columns if they exist
      if 'sunrise' in df.columns:
          df['sunrise'] = pd.to_datetime(df['sunrise'])
      if 'sunset' in df.columns:
          df['sunset'] = pd.to_datetime(df['sunset'])
          
   except Exception as e:
      raise ValueError(f"Failed to read or parse CSV: {e}")

   # Ensure correct dtypes (date already parsed)
   for col in ["wind_speed_min", "wind_speed_avg", "wind_speed_max",
               "wind_heading", "temperature", "rh", "pressure"]:
      if col in df.columns:
         df[col] = pd.to_numeric(df[col], errors='coerce')

   # # Optional: drop rows with invalid dates or NaNs in critical fields
   # df.dropna(subset=["time"], inplace=True) # Check if needed
   return df #[STATION_CSV_COLUMNS]  # Enforce column order


def reconcile_station_dataframe(df):
   """
   Ensure the dataframe matches the REQUIRED_COLUMNS format.
   Fills missing columns with NaN and reorders appropriately.
   """
   df = df.copy()

   # Use numpy.nan for missing values
   df = df.mask(df.isnull(), np.nan)

   # Drop columns not in schema
   df = df[[col for col in df.columns if col in STATION_CSV_COLUMNS]]

   # Add missing columns as NaN
   for col in STATION_CSV_COLUMNS:
      if col not in df.columns:
         df[col] = np.nan

   # Reorder
   df = df[STATION_CSV_COLUMNS]
   df.set_index('time', inplace=True)
   if not validate_station_df(df):
      LG.critical('Invalid df formed')
      sys.exit(1)
   return df


def get_actual_coordinates(lat, lon):
   """
   Queries OWM to get the 'actual' coordinates of the nearest station/grid point
   used by the API.
   """
   base_url = "https://api.openweathermap.org/data/2.5/weather"
   url = f"{base_url}?lat={lat}&lon={lon}&appid={APPID}"
   
   try:
      print(f"Fetching: {lat}, {lon} ...", end=" ", flush=True)
      response = requests.get(url, timeout=10)
      response.raise_for_status()
      data = response.json()
      
      coord = data.get('coord', {})
      new_lat = coord.get('lat')
      new_lon = coord.get('lon')
      name_api = data.get('name')
      
      if new_lat is None or new_lon is None:
         print("FAILED (No coord in response)")
         return None, None, None
         
      print(f"DONE -> {new_lat}, {new_lon} ({name_api})")
      return new_lat, new_lon, name_api
      
   except Exception as e:
      print(f"ERROR: {e}")
      return None, None, None


def update_station_coords_with_api(filename):
   file_path = Path(filename)
   if not file_path.exists():
      print(f"File not found: {filename}")
      return

   print(f"\nProcessing {filename}...")
   df = pd.read_csv(file_path)
   
   changes = 0
   for index, row in df.iterrows():
      lat = row['lat']
      lon = row['lon']
      
      new_lat, new_lon, new_name = get_actual_coordinates(lat, lon)
      
      if new_lat is not None and new_lon is not None:
         # Check if different enough or name changed
         name_changed = False
         if 'name' in df.columns:
             old_name = str(row['name'])
             if old_name != new_name:
                 df.at[index, 'name'] = new_name
                 name_changed = True
                 print(f"   Name update: {old_name} -> {new_name}")

         if abs(lat - new_lat) > 1e-5 or abs(lon - new_lon) > 1e-5 or name_changed:
            df.at[index, 'lat'] = new_lat
            df.at[index, 'lon'] = new_lon
            changes += 1
      
      # Be nice to the API
      time.sleep(0.5)
      
   if changes > 0:
      print(f"Usage: Updating {filename} with {changes} changed coordinates.")
      df.to_csv(file_path, index=False)
   else:
      print(f"No changes needed for {filename}.")
