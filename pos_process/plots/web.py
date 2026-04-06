#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import log_help
import logging
LG = logging.getLogger(f'main.{__name__}')
LGp = logging.getLogger(f'perform.{__name__}')

import os
here = os.path.dirname(os.path.realpath(__file__))
HOME = os.getenv('HOME')

import matplotlib as mpl
mpl.use('Agg')

import gc  #XXX

from . import geography as geo
from . import fields as fplots
from . import utils as ut
import matplotlib.pyplot as plt

from dataclasses import dataclass
from typing import Callable, Optional, Dict, Any
from time import time

@dataclass
class PlotLayer:
    name: str
    func: Callable
    needs_extent: bool = False
    apply_zooms: bool = True
    kwargs: Optional[Dict[str, Any]] = None


@log_help.timer(LG, LGp)
def generate_background(out_dir, geometry, csv_dir=f'configs',
                        force=False, zooms={}, ext='webp'):
   """
   plot background layers: terrain, admin boundaries, takeoffs,
   cities, rivers...
   All this layers are expected to be placed in the common folder
   /storage/PLOTS/Spain6_1/d0[1-2]/
   force: [bool] if False, plot layer only if file is not present (this
                 allows us to avoid plotting the same background layers
                 for every hour)
   zooms: [list] list of [left,right,bottom,top] limits to plot zoomed
                 snapshots of the maps
   """
   extent = geometry["borders"]
   save_func = ut.save_figure

   plot_layers = [
         PlotLayer("terrain", geo.plot_terrain, needs_extent=True),
         PlotLayer("meridian", geo.parallel_and_meridian, needs_extent=True),
         PlotLayer("rivers", geo.rivers_plot),
         PlotLayer("ccaa", geo.ccaa_plot),
         PlotLayer("roads", geo.road_plot),
         # takeoffs
         PlotLayer("takeoffs", geo.csv_plot,
                   kwargs={"csv_fname": f"{csv_dir}/takeoffs.csv",
                           "marker": "x"}),
         PlotLayer("takeoffs_names", geo.csv_names_plot,
                   kwargs={"csv_fname": f"{csv_dir}/takeoffs.csv"}),
         # cities
         PlotLayer("cities", geo.csv_plot,
                   kwargs={"csv_fname": f"{csv_dir}/cities.csv",
                           "marker": "o"}),
         PlotLayer("city_names", geo.csv_names_plot,
                   kwargs={"csv_fname": f"{csv_dir}/cities.csv"}),
         # peaks
         PlotLayer("peaks", geo.csv_plot,
                   kwargs={"csv_fname": f"{csv_dir}/peaks.csv",
                           "marker": "^"}),
         PlotLayer("peaks_names", geo.csv_names_plot,
                   kwargs={"csv_fname": f"{csv_dir}/peaks.csv"}),
         ]
   for layer in plot_layers:
      fname = out_dir / f"{layer.name}.{ext}"
      if not fname.is_file() or force: 
         LG.info(f"Plotting {layer.name}")
         ax, crs_data = geo.setup_plot(geometry)

         kwargs = layer.kwargs or {}
         if layer.needs_extent: layer.func(ax, crs_data, extent, **kwargs)
         else: layer.func(ax, crs_data, **kwargs)

         save_func(ax, fname.with_suffix(''), ext=ext)
         ut.save_zooms(ax, crs_data, zooms, out_dir, layer.name, save_func)
      else:
         LG.warning(f"Skipping plot {layer.name}. File {fname} already exists")


@log_help.timer(LG, LGp)
def generate_scalars(WRF, config_path='configs/plots.ini',
                     zooms={}, force=False, ext='webp'):
   """
   Generate and save scalar field plots (contourf) for a variety of
   meteorological variables extracted from WRF output and DrJack diagnostics.

   This function loops through a predefined list of scalar fields,
   configures their plotting parameters based on an INI file,
   and produces:
     - a full-domain image
     - zoomed versions (if provided)
     - one shared colorbar per field (only once per variable)

   Parameters
   ----------
   WRF : CalcData
       An instance of the CalcData class containing WRF output, metadata,
       and derived DrJack variables.
   config_path : str, optional
       Path to the `plots.ini` configuration file which defines vmin, vmax,
       colormap, levels, units, and title for each scalar variable.
   zooms : dict, optional
       Dictionary of named zoom regions, where each value is a (left, right,
       bottom, top) tuple in lat/lon coordinates.
       Used to generate zoomed plot versions.

   Notes
   -----
   - Fields like `t2m` are converted to Celsius internally.
   - Output images are saved in `WRF.paths["plots_daily"]`.
   - Shared colorbars are saved in `WRF.paths["plots_common"]`.
   - Zoomed images are saved using `save_zooms()`.

   Returns
   -------
   None
       Saves the generated plots directly to disk.
   """
   out_dir = WRF.paths['plots_daily']
   wrf = WRF.wrf_vars
   drjack = WRF.drjack_vars
   lons = wrf["lons"]
   lats = wrf["lats"]
   save_func = ut.save_figure

   # Map of property name -> 2D data array
   #XXX gust missing
   #    tdif missing
   fields = {
       'sfcwind'   : wrf['wspd10'].values,
       'wind1500'  : wrf['wspd1500'].values,
       'wind2000'  : wrf['wspd2000'].values,
       'wind2500'  : wrf['wspd2500'].values,
       'wind3000'  : wrf['wspd3000'].values,
       'cape'      : wrf['cape'].values,
       'rain'      : wrf['rain'].values,
       'lowfrac'   : wrf['low_cloudfrac'].values,
       'midfrac'   : wrf['mid_cloudfrac'].values,
       'highfrac'  : wrf['high_cloudfrac'].values,
       'blcloudpct': wrf['blcloudpct'].values,
       't2m'       : wrf['t2m'].values - 273.15,  #XXX ejem...
       'blwind'    : drjack['blwind'].values,
       'bltopwind' : drjack['bltopwind'].values,
       'hglider'   : drjack['hglider'].values,
       'wstar'     : drjack['wstar'].values,
       'zsfclcl'   : drjack['zsfclcl'].values,
       'zblcl'     : drjack['zblcl'].values,
       'wblmaxmin' : drjack['wblmaxmin'].values,
   }

   config = ut.load_config(config_path)
   local_time = WRF.meta["valid_time"] + ut.utc_shift()
   fmt1 =  '%Y-%m-%d_%H:%M'
   date_label =  f"valid: {WRF.meta['valid_time'].strftime(fmt1)}z\n"
   date_label += f"  GFS: {WRF.meta['gfs_batch'].strftime(fmt1)}\n"
   date_label += f" plot: {WRF.meta['created'].strftime(fmt1)}"


   for name, field in fields.items():
      t0 = time()
      LG.info(f"Plotting: {name}")
      factor, vmin, vmax, delta, levels,\
                          cmap, units, title = ut.scalar_props(config, name)
      LG.debug(f'{name} factor: {factor}')
      LG.debug(f'{name} vmin: {vmin}')
      LG.debug(f'{name} vmax: {vmax}')
      LG.debug(f'{name} delta: {delta}')
      LG.debug(f'{name} levels: {levels}')
      full_title = f"{title} {date_label}"

      ax, crs_data = geo.setup_plot(WRF.geometry)
      fplots.scalar_plot(ax, crs_data, lons, lats, field * factor,
                          delta, vmin, vmax, cmap, levels=levels,
                          inset_label=date_label, prop_name=name)

      fname = WRF.paths['plots_daily'] / f"{WRF.tail_h}_{name}"
      hname = f"{WRF.tail_h}_{name}"
      save_func(ax, fname)
      aux = WRF.paths['plots_daily']
      ut.save_zooms(ax, crs_data, zooms, aux, hname, save_func)
      fig = ax.figure
      plt.close(fig)
      del ax, fig
      gc.collect()

      # Colorbar
      # fname = WRF.paths['plots_common'] / name
      fname = WRF.paths['plots_common'] / f"{name}.{ext}"
      if not fname.is_file() or force:
         LG.debug(f'plotting colorbar {name}')
         ax = fplots.plot_colorbar(cmap,delta,vmin,vmax, levels,
                                        name=fname,units=units,
                                        fs=15,norm=None,extend='max')
         save_func(ax, fname.with_suffix(''))
         fig = ax.figure
         plt.close(fig)
         del ax, fig
         gc.collect()
         LG.info(f'plotted colorbar {name}')
      else:
         LG.info(f'colorbar {name} already present')
      LG.info(f"Full Time for {name}: {time()-t0:.4f}s")



@log_help.timer(LG, LGp)
def generate_vectors(WRF, config_path='configs/plots.ini', zooms={}):
   """
   Generate and save vector field plots (wind barbs or streamlines)
   for horizontal wind components derived from WRF and DrJack data.

   This function loops over a predefined dictionary of vector fields,
   applies scaling and visual styling from an INI configuration file,
   and saves:
     - full-domain vector plots
     - zoomed versions (if zooms are defined)

   Parameters
   ----------
   WRF : CalcData
       Instance of the CalcData class containing WRF and DrJack output,
       metadata, and configuration paths.
   config_path : str, optional
       Path to the INI configuration file (default is 'plots.ini').
       This file provides plotting parameters such as factor, colormap,
       limits, and title for each variable.
   zooms : dict, optional
       Dictionary of named zoom regions where each value is a tuple
       (left, right, bottom, top) in lat/lon coordinates.
       Zooms are saved using `save_zooms()`.

   Notes
   -----
   - Vector fields must be shaped as (2, ny, nx), representing (u, v).
   - Supported fields include winds at various heights and boundary layers.
   - Output filenames follow the pattern: {timestamp}_{name}_vec.webp
   - Colorbar is not generated unless explicitly included.

   Returns
   -------
   None
       Plots are saved to disk in WRF.paths['plots_daily'] and zooms are handled accordingly.
   """
   out_dir = WRF.paths['plots_daily']
   wrf = WRF.wrf_vars
   drjack = WRF.drjack_vars
   lons = wrf["lons"]
   lats = wrf["lats"]
   save_func = ut.save_figure

   # Map of property name -> 2D data array
   #XXX gust missing
   #    tdif missing
   fields = {
       'sfcwind'   : wrf['uvmet10'].values,
       'wind1500'  : wrf['uvmet1500'].values,
       'wind2000'  : wrf['uvmet2000'].values,
       'wind2500'  : wrf['uvmet2500'].values,
       'wind3000'  : wrf['uvmet3000'].values,
       # 'uvblavg'   : drjack['uvblavg'],
       # 'uvtop'     : drjack['uvtop'],
       'blwind'    : drjack['uvblavg'],
       'bltopwind' : drjack['uvtop'],
   }

   config = ut.load_config(config_path)
   local_time = WRF.meta["valid_time"] + ut.utc_shift()
   fmt1 =  '%Y-%m-%d_%H:%M'
   date_label =  f"valid: {WRF.meta['valid_time'].strftime(fmt1)}z\n"
   date_label += f"  GFS: {WRF.meta['gfs_batch'].strftime(fmt1)}\n"
   date_label += f" plot: {WRF.meta['created'].strftime(fmt1)}"


   for name, field in fields.items():
      # Stream plots
      LG.info(f"Streamplots: {name}")
      factor, vmin, vmax, delta, levels,\
                          cmap, units, title = ut.scalar_props(config, name)
      full_title = f"{title} {date_label}"

      ax, crs_data = geo.setup_plot(WRF.geometry)
      C = fplots.vector_plot(ax, crs_data, lons, lats, field * factor)

      fname = WRF.paths['plots_daily'] / f"{WRF.tail_h}_{name}_vec"
      vname = f"{WRF.tail_h}_{name}_vec"
      save_func(ax, fname)
      aux = WRF.paths['plots_daily']
      ut.save_zooms(ax, crs_data, zooms, aux, vname, save_func)
      # Wind barbs
      ax, crs_data = geo.setup_plot(WRF.geometry)
      fplots.barbs_plot(ax,crs_data, lons,lats,field, color='k')
      fname = WRF.paths['plots_daily'] / f"{WRF.tail_h}_{name}_barb"
      vname = f"{WRF.tail_h}_{name}_barb"
      # save_func(ax, fname)   #XXX skip windbarbs for large domains
      aux = WRF.paths['plots_daily']
      ut.save_zooms(ax, crs_data, zooms, aux, vname, save_func)
      LG.info(f"Windbarbs: {name}")
      fig = ax.figure
      plt.close(fig)
