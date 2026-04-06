#!/usr/bin/env python3
# -*- coding: utf-8 -*-


import pandas as pd
from pathlib import Path
here = Path(__file__).resolve().parent
import logging
import sys

import stations.utils as sut
from stations.utils import save_station_csv, validate_station_df
from stations.schema import STATION_CSV_COLUMNS
from stations.api import openweathermap
import utils as ut
from plots.baliza import compare

# Setup logger
LG = logging.getLogger("main")
logging.basicConfig(
   level=logging.WARNING,
   format='[%(asctime)s] %(levelname)s - %(message)s',
   datefmt='%Y/%m/%d %H:%M:%S'
)
# File handler
log_file = Path("logs/stations_downloader.log")
file_handler = logging.FileHandler(log_file, mode='a')
file_handler.setFormatter(logging.Formatter(
    '[%(asctime)s] %(name)s:%(levelname)s - %(message)s',
    datefmt='%Y/%m/%d %H:%M:%S'
))
LG.addHandler(file_handler)

def download(configfile=None):
   """
   Download station observation data for today and store it in the
   appropriate observations folder.
   """
   paths = ut.load_config_or_die(configfile)

   for domain in ['d01','d02']:
      STATIONS_CSV = paths['configs_folder'] / f"stations_{domain}.csv"
      OUT_DIR = paths['data_folder'] / "stations/observations"
      ut.check_directory(OUT_DIR)

      if not STATIONS_CSV.exists():
         LG.critical(f"Missing config file: {STATIONS_CSV}")
         continue

      # Leer sin cabecera e indicar que las 3 columnas son: lat, lon, name
      df = pd.read_csv(STATIONS_CSV, header=None, names=["lat", "lon", "name"])

      for _, row in df.iterrows():
         try:
            name = str(row["name"]).strip()
            code = name.lower().replace(' ', '_')
            lat  = float(row["lat"])
            lon  = float(row["lon"])
            
            LG.info(f"Downloading data for station: {name} ({lat}, {lon})")
            
            # Direct call to OWM backend
            data_df = openweathermap.download_data(lat=lat, lon=lon)
            save_station_csv(data_df, OUT_DIR / f"{code}.csv")
            LG.info(f"Saved {len(data_df)} obs rows for {name}")
         except Exception as e:
            LG.error(f"Failed to fetch or save station {row.get('name', 'Unknown')}: {e}")

def plot(configfile=None):
   """
   Generate comparison plots for all configured stations that have both prediction and observation data.
   """
   LG.info('plotting stations')
   paths = ut.load_config_or_die(configfile)
   PLOTS = paths['plots_stations']
   PREDICTIONS = paths['data_folder'] / "stations/predictions"
   OBSERVATIONS = paths['data_folder'] / "stations/observations"
   
   ut.check_directory(PLOTS)

   for domain in ['d01', 'd02']:
      STATIONS_CSV = paths['configs_folder'] / f"stations_{domain}.csv"
      if not STATIONS_CSV.exists():
         continue
         
      # Leer listado de estaciones (sin cabecera)
      df = pd.read_csv(STATIONS_CSV, header=None, names=["lat", "lon", "name"])
      
      for _, row in df.iterrows():
         name = str(row["name"]).strip()
         code = name.lower().replace(' ', '_')
         
         pred = PREDICTIONS / f"{code}.csv"
         obs  = OBSERVATIONS / f"{code}.csv"
         fout = PLOTS / f"{code}.webp"
         
         if pred.exists() and obs.exists():
            LG.debug(f"station: {pred}")
            try:
               df_pred = sut.read_station_csv(pred)
               df_obs  = sut.read_station_csv(obs)
               title = f"Baliza {name}"
               compare(df_obs, df_pred, title=title, fout=fout)
            except Exception as e:
               LG.error(f"Failed to plot {name}: {e}")
         else:
            LG.debug(f"Missing pred or obs for {name}, skipping plot.")


def main():
   import argparse
   parser = argparse.ArgumentParser(description="Download and plot station data")
   parser.add_argument("--config", default=None, help="Path to config.ini")
   args = parser.parse_args()

   download(args.config)
   plot(args.config)

if __name__ == "__main__":
   main()
