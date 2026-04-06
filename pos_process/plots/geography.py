#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import log_help
import logging
LG = logging.getLogger(f'main.{__name__}')
LGp = logging.getLogger(f'perform.{__name__}')

import matplotlib as mpl
mpl.use('Agg')

import matplotlib.pyplot as plt
import matplotlib.patheffects as PathEffects
from matplotlib.colors import LightSource
import numpy as np
import cartopy.crs as ccrs
from cartopy.feature import NaturalEarthFeature
import cartopy.feature as cfeature
import pandas as pd
from pathlib import Path
import rasterio
from rasterio.merge import merge
import os


@log_help.timer(LG, LGp)
def setup_plot(geometry, proj='lambert',transparent=True):
   reflat  = geometry["center_lat"]
   reflon  = geometry["center_lon"]
   extent  = geometry["borders"]
   crs_data = ccrs.PlateCarree()
   if proj == 'lambert':
      crs_plot = ccrs.LambertConformal(reflon,reflat)
   elif proj == 'mercator':
      crs_plot = ccrs.Mercator()
   fig = plt.figure(figsize=(11,9)) #, frameon=False)
   ax  = fig.add_axes([0,0,0.99,1], projection=crs_plot)
   # extent = left, right, bottom, top
   ax.set_extent(extent, crs=crs_data)
   ax.set_autoscale_on(False)
   if transparent:
      # Remove axes frame and ticks
      ax.set_frame_on(False)
      ax.set_xticks([])
      ax.set_yticks([])
   return ax, crs_data


@log_help.timer(LG, LGp)
def plot_terrain(ax, crs_data, extent, ve=0.3, tif_dir="terrain_tif"):
   """
   Plot hillshaded terrain background using GEBCO .tif files.

   Parameters
   ----------
   ax : GeoAxes
       The map axis where terrain will be plotted.
   crs_data : cartopy CRS
       The CRS of the terrain raster data (typically PlateCarree).
   extent : tuple
       (left, right, bottom, top) — plot domain in lat/lon.
   ve : float
       Vertical exaggeration for hillshading.
   tif_dir : str
       Path to directory containing .tif tiles.
   """
   left, right, bottom, top = extent
   # Load and merge all terrain tiles
   tif_dir = Path(tif_dir)
   if not tif_dir.is_absolute():
      # Resolve relative to the file where this function lives
      tif_dir = Path(__file__).resolve().parents[1] / tif_dir
   tifs = sorted(Path(tif_dir).glob("*.tif"))
   if not tifs:
      LG.critical(f"No GEBCO .tif files found in: {tif_dir}")
      raise FileNotFoundError(f"No GEBCO .tif files found in: {tif_dir}")
   srcs = [rasterio.open(fname, 'r') for fname in tifs]
   buffer_deg = 2  # pad to avoid edge effects
   extent_padded = (left-buffer_deg, bottom-buffer_deg,
                    right+buffer_deg, top+buffer_deg)
   mosaic, out_trans = merge(srcs, extent_padded)
   terrain = mosaic[0,:,:]  # single-band gray elevation

   # Hillshade
   ls = LightSource(azdeg=315, altdeg=65)
   terrain = ls.hillshade(terrain, vert_exag=ve)
   extent_padded = (left-buffer_deg, right+buffer_deg,
                    bottom-buffer_deg, top+buffer_deg)

   # Plot
   ax.imshow(terrain, extent=extent_padded,
             origin='upper', cmap='gray',interpolation='bicubic',
             aspect='equal', zorder=0, transform=crs_data)
   return ax, crs_data

@log_help.timer(LG, LGp)
def parallel_and_meridian(ax, crs_data, extent, nx=1,ny=1):
   left,right,bottom,top = extent
   lcs = 'k--'
   D = 1
   # Plotting meridian
   for x in range(int(left-D), int(right+D)):
      if x%nx ==0:
         ax.plot([x,x],[bottom-D,top+D], lcs, transform=crs_data)
         ax.plot([x+.5,x+.5],[bottom-D,top+D], 'k:', transform=crs_data, alpha=.7)
         ax.text(x,bottom*1.0004, f'{x}°', transform=crs_data, clip_on=True)
   # Plotting parallels
   for y in range(int(bottom-D), int(top+D)):
      if y%ny == 0:
         ax.plot([left-D,right+D],[y,y], lcs, transform=crs_data)
         ax.plot([left-D,right+D],[y+.5,y+.5], 'k:', transform=crs_data, alpha=.7)
         ax.text(left,y, f'{y}°', va='top', transform=crs_data, clip_on=True)
   return ax, crs_data

@log_help.timer(LG, LGp)
def rivers_plot(ax, crs_data):
   rivers = NaturalEarthFeature('physical',
                                'rivers_lake_centerlines_scale_rank',
                                '10m', facecolor='none')
   ax.add_feature(rivers, lw=2 ,edgecolor='C0',zorder=50)
   rivers = NaturalEarthFeature('physical', 'rivers_europe',
                                '10m', facecolor='none')
   ax.add_feature(rivers, lw=2 ,edgecolor='C0',zorder=50)
   for field in ['lakes','lakes_historic','lakes_pluvial','lakes_europe']:
       water = NaturalEarthFeature('physical', field, '10m')
       ax.add_feature(water, lw=2 ,edgecolor='C0',
                      facecolor=cfeature.COLORS['water'],zorder=50)
   return ax, crs_data

@log_help.timer(LG, LGp)
def sea_plot(ax, crs_data):
   """
   XXX Not working
   """
   sea = NaturalEarthFeature('physical', 'bathymetry_all', '10m') #, facecolor='none')
   ax.add_feature(sea, lw=2) # ,edgecolor='C0',zorder=50)
   return ax, crs_data

@log_help.timer(LG, LGp)
def ccaa_plot(ax, crs_data):
   provin = NaturalEarthFeature('cultural', 'admin_1_states_provinces_lines',
                                            '10m', facecolor='none')
   country = NaturalEarthFeature('cultural', 'admin_0_countries', '10m',
                                                   facecolor='none')
   ax.add_feature(provin, lw=2 ,edgecolor='k',zorder=50)
   ax.add_feature(country,lw=2.3, edgecolor='k', zorder=51)
   return ax, crs_data

@log_help.timer(LG, LGp)
def road_plot(ax, crs_data):
   roads = NaturalEarthFeature('cultural', 'roads',
                                            '10m', facecolor='none')
   ax.add_feature(roads, lw=2 ,edgecolor='w',zorder=51)
   ax.add_feature(roads, lw=3 ,edgecolor='k',zorder=50)
   return ax, crs_data


def read_csv(fname):
   try:
      df = pd.read_csv(fname, header=None, names=["lat", "lon", "name"])
   except pd.errors.EmptyDataError:
      df = pd.DataFrame(columns=["lat", "lon", "name"])
   Yt = df["lat"].values
   Xt = df["lon"].values
   names = df["name"].values
   return Xt,Yt,names

@log_help.timer(LG, LGp)
def csv_plot(ax, crs_data, csv_fname,marker='x'):
   Xt, Yt, _ = read_csv(csv_fname)
   ax.scatter(Xt,Yt,s=40,c='r',marker=marker,transform=crs_data)
   return ax, crs_data

@log_help.timer(LG, LGp)
def csv_names_plot(ax, crs_data, csv_fname):
   Xt, Yt, names = read_csv(csv_fname)
   for x,y,name in zip(Xt,Yt,names):
      txt = ax.text(x,y,name, horizontalalignment='center',
                              verticalalignment='center',
                              color='k',fontsize=13,
                              transform=crs_data)
      txt.set_path_effects([PathEffects.withStroke(linewidth=5,
                                                   foreground='w')])
      txt.set_clip_on(True)
   return ax, crs_data

