#!/usr/bin/python3
# -*- coding: UTF-8 -*-

# Sys modules
from pathlib import Path
import os, sys, argparse
try:
    import psutil
except ImportError:
    psutil = None
here = os.path.dirname(os.path.realpath(__file__))
HOME = os.getenv('HOME')

# Loggings
import logging
import log_help
LG = logging.getLogger("main")
LGp = logging.getLogger("perform")

# RASP modules
import pandas as pd
import utils as ut
from calc_data import CalcData
# stations
import stations
# meteograms
from meteogram_writer import make_meteogram_timestep, append_to_meteogram
# web, sounding & meteogram
import plots
import gc


def existing_file(path):
   """Helper function for argparse to check if input file exists"""
   if not os.path.isfile(path):
      raise argparse.ArgumentTypeError(f"File not found: {path}")
   return path

def parse_args():
   """
   Define input options
   - filepath: wrfout file to process
   - config: path to config.ini file
   """
   parser = argparse.ArgumentParser(
       description="Post-process a WRF output file and generate plots." )
   parser.add_argument("filepath",  type=existing_file,
          help="Path to the WRF NetCDF file (wrfout_<domain>_<date>)" )
   parser.add_argument("--config", default=str(Path(here).parent / "config.ini"),
                       help=f"Path to config.ini (default: {Path(here).parent}/config.ini)")
   return parser.parse_args()

@log_help.timer(LG,LGp)
def process_file(fname, configfile, LG):
   """
   Run post-processing for wrfout file
   """
   LG.info(f"Processing file: {fname}")
   paths = ut.load_config_or_die(configfile)

   plots_folder   = paths['plots_folder']
   data_folder    = paths['data_folder']
   configs_folder = paths['configs_folder']
   plots_ini      = paths['plots_ini']
   zooms_ini      = paths['zooms_ini']

   A = CalcData(fname, OUT_folder=plots_folder, DATA_folder=data_folder)
   domain = A.meta['domain']
   zooms = ut.load_zooms(zooms_ini, domain=domain)

   # Read station metadata file
   stations_csv = Path(configs_folder) / f"stations_{domain}.csv"

   if not stations_csv.exists():
      LG.warning(f"Station list not found: {stations_csv}. Generating from zooms.ini")
      new_stations = []
      for section, bounds in zooms.items():
            try:
                left, right, bottom, top = bounds

                # Calculate center
                lat = (bottom + top) / 2
                lon = (left + right) / 2

                new_stations.append({
                    "name": section,
                    "lat": lat,
                    "lon": lon
                })
            except Exception as e:
                LG.error(f"Error parsing zoom section {section}: {e}")

      if new_stations:
          df = pd.DataFrame(new_stations)
          # Save initial CSV
          df.to_csv(stations_csv, index=False)
          LG.info(f"Created initial stations file with {len(df)} entries. Updating coords via API...")

          # Update with API
          stations.utils.update_station_coords_with_api(str(stations_csv))
      else:
          LG.warning(f"No zooms found for domain {domain} in {zooms_ini}. Skipping station generation.")

   if stations_csv.exists() and stations_csv.stat().st_size > 0:
      LG.info(f"Reading station list from: {stations_csv}")
      try:
          df = pd.read_csv(stations_csv)
      except pd.errors.EmptyDataError:
          df = pd.DataFrame()

      if df.empty:
          LG.warning(f"Station list is empty: {stations_csv}")

      predictions_folder = A.paths["data_stations"] / "predictions"
      ut.check_directory(predictions_folder)  # create if missing
      for i, row in df.iterrows():
         lat, lon = float(row["lat"]), float(row["lon"])
         # Use the original name from CSV to match Zoom section
         original_name = str(row["name"]).strip()
         station_id = original_name.lower().replace(' ', '_')

         # Strategy 2 (Robust): Check if the station falls into ANY defined zoom for this domain
         is_inside_any = False
         checked_zooms = []

         for section, bounds in zooms.items():
             try:
                 z_left, z_right, z_bottom, z_top = bounds

                 checked_zooms.append(section)

                 if (z_bottom <= lat <= z_top) and (z_left <= lon <= z_right):
                     is_inside_any = True
                     LG.debug(f"Station '{original_name}' is inside zoom '{section}'")
                     break # Found one match, good enough
             except: pass

         if not is_inside_any and checked_zooms:
             LG.warning(f"Station '{original_name}' coords ({lat:.4f},{lon:.4f}) are NOT contained in any zoom for {domain} (Checked: {checked_zooms})")
         elif not checked_zooms:
             LG.debug(f"No zooms defined for {domain}, skipping bounds check.")

         LG.info(f"Saving prediction for station '{station_id}'")
         stations.extract_wrf.save_prediction(A, station_id, lat, lon, predictions_folder)
   else:
      LG.warning(f"No stations CSV available for {domain}. Skipping station predictions.")

   # Background (it will skip if the files already exist)
   LG.info("==== Generating background maps ====")
   plots.web.generate_background(A.paths['plots_common'], A.geometry, csv_dir=configs_folder, zooms=zooms)

   # Scalars: T2, RH, Wstar, CAPE, etc
   LG.info("Plotting scalar fields...")
   plots.web.generate_scalars(A, config_path=plots_ini, zooms=zooms)

   # Vectors: winds, streamlines, etc
   LG.info("Plotting vector fields...")
   plots.web.generate_vectors(A, config_path=plots_ini, zooms=zooms)

   # Soundings & meteograms
   # Get points of interest for soundings and meteograms
   LG.info("Plotting soundings and meteograms")
   soundings_csv = Path(configs_folder) / f"soundings_{domain}.csv"
   if soundings_csv.exists() and soundings_csv.stat().st_size > 0:
      try:
         df_raw = pd.read_csv(soundings_csv, header=None).fillna('')
         if len(df_raw.columns) >= 3:
             df = df_raw.iloc[:, :3]
             df.columns = ['lat', 'lon', 'name']
         else:
             df = pd.DataFrame(columns=['lat', 'lon', 'name'])
      except pd.errors.EmptyDataError:
         df = pd.DataFrame(columns=['lat', 'lon', 'name'])
   else:
      LG.warning(f"Soundings file missing or empty: {soundings_csv}")
      df = pd.DataFrame(columns=['lat', 'lon', 'name'])

   # Plot sounding and meteogram for each point
   for _, row in df.iterrows():
      lat, lon, name = row['lat'], row['lon'], row['name']
      code = str(name).strip().lower().replace(' ', '_')

      # Sounding
      fout = A.paths["plots_daily"] / f"{A.tail_h}_sounding_{code}.webp"
      plots.sounding.skew_t_plot(A, lat, lon, name=name, fout=fout)

      # Meteogram
      day_nc = A.paths["data_meteograms"] / f"meteogram_{code}.nc"
      ds = make_meteogram_timestep(A, lat, lon)
      ds_full = append_to_meteogram(ds, day_nc)
      if len(ds_full["time"]) >= 2:
         fout = A.paths["plots_daily"] / f"meteogram_{code}.webp"
         plots.meteogram.plot_meteogram(day_nc, name=name, fout=fout)
      else:
         LG.debug(f"Skipping meteogram plot for {code} (only one time point)")

   LG.info(f"Finished processing {fname}")

def main():
   args = parse_args()
   fname = args.filepath
   fname = Path(fname)
   config_file = args.config

   # Get common variables for setting up LOG
   is_cron = bool(os.getenv('RUN_BY_CRON'))
   domain = ut.get_domain(fname)
   date = ut.file2date(fname)

   # Prepare standard GFSbatch path
   # batch_path = fname.parent / "batch.txt"
   # batch = ut.get_GFSbatch(batch_path)
   batch = ut.get_batch_from_metadata(fname)
   script_path = os.path.realpath(__file__)

   LG, LGp = log_help.batch_logger(script_path, domain, batch, is_cron, log_dir='logs')
   LG.info("=================================================")
   LG.info("=                New run started                =")
   LG.info("=================================================")
   LG.info(f"Cron: {is_cron}")
   try:
      process_file(fname, config_file, LG)
      gc.collect()
   except Exception as e:
      LG.exception(f"Failed to process file {fname}: {e}")
      sys.exit(1)
   if psutil:
       mem = psutil.Process(os.getpid()).memory_info().rss / 1024**2
       LG.critical(f"Final memory before exit: {mem:.2f} MB")
   else:
       LG.info("Final memory: psutil not available")

if __name__ == "__main__":
   main()
