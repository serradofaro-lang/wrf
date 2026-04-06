#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import log_help
import logging
LG = logging.getLogger(f'main.{__name__}')
LGp = logging.getLogger(f'perform.{__name__}')

import os, sys
here = os.path.dirname(os.path.realpath(__file__))
HOME = os.getenv('HOME')
from pathlib import Path
import datetime as dt
import utils as ut
import extract_wrf as ex

class CalcData(object):
   """
   Post-processed WRF wrapper class

   Loads and organizes WRF data and derived quantities for a single file
     - Validates filename and metadata consistency
     - Extracts WRF and DrJack variables
     - Manages output/data paths (daily + common)
     - Optionally compares with previous timestep for rain calculations

   Attributes:
      meta (dict): Metadata like domain, valid_time, batch info
      paths (dict): Resolved paths for wrfout, plots, and data output
      wrf_vars (dict): Native WRF variables from the file
      drjack_vars (dict): Derived paragliding-related quantities
   """
   @log_help.timer(LG, LGp)
   def __init__(self, fname, OUT_folder='.', DATA_folder='.'):
      """
      Initialize a CalcData instance for post-processing a single WRF
      output file
      Args:
       - fname (str or Path): Path to the WRF NetCDF file
       - OUT_folder (str or Path): Root output directory for plots
       - DATA_folder (str or Path): Root output directory for data (e.g., .nc)
      Raises:
       - FileNotFoundError: If the input file does not exist
       - ValueError: If filename date and metadata date do not match
      """
      fname = Path(fname).resolve()
      if not fname.is_file():
         LG.critical(f'FileNotFound: {fname}')
         sys.exit(1)

      info = ex.wrfout_info(fname)
      if ut.file2date(fname) != info['date']:
         raise ValueError("WRF filename date and internal date do not match")

      # Common MetaData
      self.meta = {
            "fname"     : fname,
            "domain"    : info['domain'],
            "valid_time": info['date'],
            "gfs_batch" : info['GFS_batch'],
            "created"   : info['creation_date'],
            "date_fmt"   : info["date"].strftime("%Y%m%d"),
            }
      self.geometry = {
            "center_lat": info['reflat'],
            "center_lon": info['reflon'],
            "bounds"    : info["bounds"],
            }
      self.geometry['borders'] = self.borders

      domain = self.meta['domain']
      date_fmt = self.meta["date_fmt"]

      self.paths = {
            "wrfout"         : fname,
            "wrfout_folder"  : fname.parent,
            "processed"      : fname.parent/"processed",
            "data_meteograms": Path(DATA_folder)/'meteograms'/domain/date_fmt,
            "data_stations"  : Path(DATA_folder)/'stations', #domain/date_fmt,
            "data_daily"     : Path(DATA_folder)/domain/date_fmt,
            "plots_common"   : Path(OUT_folder)/domain,
            "plots_daily"    : Path(OUT_folder)/domain/date_fmt,
            }

      for k,v in self.meta.items():
         LG.debug(f'{k}: {v}')
      for k,v in self.paths.items():
         LG.debug(f'{k}: {v}')

      # Get the actual WRF data
      self.ncfile = info['ncfile']
      prevnc = self.get_previous_ncfile()

      # Extract WRF data
      self.wrf_vars = ex.wrf_vars(self.ncfile, prevnc=prevnc)
      LG.info(f"Loaded {len(self.wrf_vars)} WRF variables")
      # Free memory
      del prevnc

      # Calculate DrJack's properties
      self.drjack_vars = ex.drjack_vars(self.wrf_vars)
      LG.info(f"Computed {len(self.drjack_vars)} derived variables")

      LG.info(f"Checking matrices sizes")
      self._sanity_check_shapes()

      # Check relevant folders
      for key in ["data_daily", "plots_common", "plots_daily",
                  "data_meteograms", "data_stations", "processed"]:
         ut.check_directory(self.paths[key])

   @log_help.timer(LG, LGp)
   def _sanity_check_shapes(self):
      """Check that all data matrices have the same XY sizes"""
      aux = []
      for k,v in self.wrf_vars.items():
         aux.append(v.shape[-2:])
      for k,v in self.drjack_vars.items():
         aux.append(v.shape[-2:])
      if (len(set(aux))) > 1:
         LG.critical("Inconsistent spatial shapes among variables:")
         # for shape in set(aux):
         #    LG.error(f" - shape: {shape}")
         for k,v in self.wrf_vars.items():
            LG.error(f"{k}: v.shape[-2:]")
         for k,v in self.drjack_vars.items():
            LG.error(f"{k}: v.shape[-2:]")
         raise ValueError("WRF and derived variables have mismatched shapes")

   @property
   def tail_h(self):
      return self.meta["valid_time"].strftime("%H%M")
   @property
   def tail_d(self):
      return self.meta["valid_time"].strftime("%Y%m%d")
   def get_previous_ncfile(self):
      """
      Find and return the previous wrfout NetCDF file, or None if not found
      """
      prevnc = None
      h1 = dt.timedelta(hours=1)
      prev_time = self.meta["valid_time"] - h1
      search_paths = [ self.paths["processed"], self.paths["wrfout_folder"] ]
      for folder in search_paths:
         try:
            LG.debug(f"Looking for previous wrfout in {folder}")
            prev_path = ut.date2file(prev_time, self.meta["domain"], folder)
            info_prev = ex.wrfout_info(prev_path)
            prevnc = info_prev["ncfile"]
            LG.debug(f"Found previous wrfout: {prev_path}")
            break
         except FileNotFoundError:
            LG.warning(f"Previous wrfout not found in {folder}")
            continue
      return prevnc
   @property
   def borders(self):
      bounds = self.geometry['bounds']
      return bounds.bottom_left.lon, bounds.top_right.lon, \
             bounds.bottom_left.lat, bounds.top_right.lat
   def __str__(self):
      summary = [
            f"CalcData Summary:",
            f"  Domain        : {self.meta['domain']}",
            f"  Valid Time    : {self.meta['valid_time']:%Y-%m-%d %H:%M}",
            f"  GFS Batch     : {self.meta['gfs_batch']:%Y-%m-%d %H:%M}",
            f"  WRF File      : {self.paths['wrfout'].name}",
            f"  Output Folder : {self.paths['plots_daily']}",
            f"  Data Folder   : {self.paths['data_daily']}",
            f"  Variables     : {len(self.wrf_vars)} WRF, "+\
                              f"{len(self.drjack_vars)} DrJack-derived"
            ]
      return "\n".join(summary)
