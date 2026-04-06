#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import log_help
import logging
LG = logging.getLogger(f'main.{__name__}')
LGp = logging.getLogger(f'perform.{__name__}')

import os
here = os.path.dirname(os.path.realpath(__file__))
HOME = os.getenv('HOME')
STYLE_PATH = os.path.join(here, "styles", "RASP.mplstyle")

import matplotlib as mpl
mpl.use('Agg')

import sys
import datetime as dt
from . import colormaps as mcmaps
from . import utils as ut
from datetime import timedelta
import matplotlib.pyplot as plt
plt.style.use(STYLE_PATH)
from matplotlib.patches import Rectangle
import matplotlib.dates as mdates
import numpy as np
import xarray as xr
from metpy.units import units
import metpy.calc as mpcalc
import derived_quantities as dq


# helper shortcuts
p2m = mpcalc.pressure_to_height_std
m2p = mpcalc.height_to_pressure_std


def pad_array(arr):
   """
   Pad data arrays: replicate first and last rows
   """
   first = arr[0:1, :]
   last  = arr[-1:, :]
   return np.concatenate([first, arr, last], axis=0)


def get_bar_width(m):
   """
   Xaxis is in numpy datetime, this function converts minutes to width
   of the bar plots
   """
   return timedelta(minutes=m).total_seconds() / (24 * 3600)


@log_help.timer(LG, LGp)
def plot_meteogram(fname,title='',name='',fout='meteogram.webp', ext='webp'):
   """
   Input: fname is the path to an xrarray created by meteogram_writer.py which
          populates the ncfile as new wrfout files become avialable
   Layout:
                     __________________
                    |                  |  low/mid/high frac   
           [ax0]--> |                  | <-- Cloud %
                    |__________________|
                    |                  |
                    |                  |
                    |                  |
                    |                  |
           [ax ]--> |     METEOGRAM    |
                    |                  |
                    |                  |
                    |                  |
                    |__________________|
           [ax1]-->  ##################  <-- cbar

   Required properties (leys) in input ncfile:
     - time: [datetime?] Forecast time
     - terrain_height: [m] Terrain height 
     - heights: [m] Height of vertical levels in the model
     - hglider: [m] Max Height for a paraglider max(min(zblcl, zsfclcl), hcrit)
     - rain: [mm] 1h rain
     - low_cloudfrac: [%] Fraction of low clouds
     - mid_cloudfrac: [%] Fraction of mid clouds
     - high_cloudfrac: [%] Fraction of high clouds
     - zsfclcl: [m] Slightly obsolete, soon it will not be necessary
     - zblcl: [m] Slightly obsolete, soon it will not be necessary
     - umet10: [m/s] U component of 10m earth-rotated wind
     - vmet10: [m/s] V component of 10m earth-rotated wind
     - wspd: [m/s] Module of windfor all vert levels
     - umet: [m/s] U component of earth-rotated wind for all vert levels
     - vmet: [m/s] V component of earth-rotated wind for all vert levels
     - p: [hPa] Full pressure for all vert levels
     - tc: [°C] Temperature for all vert levels
     - rh: [%] Relative humidity
     - t0: [K] T2m
     - td0: [°C] TD2m

   Layers order
   ---------------------------------
   | zorder  |      quantity       |
   ---------------------------------
   |    0    |   wspd (contourf)   |
   |    1    |  thermals (hglier)  |
   |    2    | wind height (uvmet) |
   |    3    |      overcast       |
   |    4    |       cumulus       |
   |    5    |        rain         |
   |    6    |       ground        |
   |    7    | wind 10m (uvmet10)  |
   ---------------------------------
   """
   ############################ READ & PROCESS DATA #############################
   # Load dataset
   try: ds = xr.open_dataset(fname)
   except FileNotFoundError:
      LG.critical(f'Error in meteogram.py. File {fname} does not exist')
      sys.exit(1)
   UTCshift = ut.utc_shift()

   #                                       #
   #   Import and make MetPy units aware   #
   #                                       #
   ## Extract
   lat = ds.attrs.get("location_lat")
   lon = ds.attrs.get("location_lon")
   hours   = ds["time"].values                  # (n_time,)
   terrain = ds["terrain_height"].values        # (n_time,)
   heights = ds["heights"].values               # (n_time, n_level)
   hglider = ds["hglider"].values               # (n_time,)
   rain = ds["rain"].values                     # (n_time,)
   wstar = ds["wstar"].values                   # (n_time,)
   low_cloudfrac = ds["low_cloudfrac"].values   # (n_time,)
   mid_cloudfrac = ds["mid_cloudfrac"].values   # (n_time,)
   high_cloudfrac = ds["high_cloudfrac"].values # (n_time,)
   umet10  = ds["umet10"].values                # (n_time,)
   vmet10  = ds["vmet10"].values                # (n_time,)
   wspd10  = ds["wspd10"].values                # (n_time,)
   wspd    = ds["wspd"].values                  # (n_time, n_level)
   umet    = ds["umet"].values                  # (n_time, n_level)
   vmet    = ds["vmet"].values                  # (n_time, n_level)
   p       = ds['p'].values                     # (n_time, n_level)
   tc      = ds['tc'].values                    # (n_time,)
   rh      = ds['rh'].values / 100              # (n_time, n_level)
   t0      = ds["t0"].values                    # (n_time,)
   td0     = ds["td0"].values                   # (n_time,)
   GND = terrain[0] + 15  # cheap fix for the gap between the terrain and the
                          # 1st vertical layer in the model
   ## MetPy units
   p      = p      * units('hPa')
   tc     = tc     * units('degC')
   t0     = t0     * units('K')
   td0    = td0    * units('degC')
   wspd   = wspd   * units('m s-1')
   wspd10 = wspd10 * units('m s-1')
   umet10 = umet10 * units('m s-1')
   vmet10 = vmet10 * units('m s-1')
   umet   = umet   * units('m s-1')
   vmet   = vmet   * units('m s-1')
   ## Conversions
   date   = hours[0].astype('M8[ms]').astype(dt.datetime)  # for title
   hours  = hours + np.timedelta64(UTCshift)  # XXX hours is now local time!!!
   t0c    = t0.to('degC')
   umet10 = umet10.to('km h-1')
   vmet10 = vmet10.to('km h-1')
   wspd10 = wspd10.to('km h-1')
   wspd   = wspd.to('km h-1')  
   umet   = umet.to('km h-1') 
   vmet   = vmet.to('km h-1') 
   ########################################
   LG.info(f"Length meteogram data: {len(hours)}")


   # Pad frist and last hour for smooth edges
   # Convert times to pandas for easier manipulation
   times = hours
   delta_t = np.diff(times).astype("timedelta64[m]").astype(int)
   try: mean_dt = int(np.median(delta_t))  # assume uniform spacing
   except ValueError:
      LG.critical('Not enough data for a meteogram')
      sys.exit(1)

   #################################### PLOT ####################################
   # Setup the Figure layout
   hr = [2,18,.5]
   l = .08
   r = .98
   t = .97
   gs_plots = plt.GridSpec(3, 1, height_ratios=hr,hspace=0.,
                                 top=t, left=l, right=r, bottom=0.0675)
   gs_cbar  = plt.GridSpec(3, 1, height_ratios=hr,hspace=0.5,
                                 top=t, left=l, right=r, bottom=0.04)
   fig = plt.figure(figsize=(11, 13))
   # Define the axis
   ax =  fig.add_subplot(gs_plots[1,:])             # meteogram
   ax0 = fig.add_subplot(gs_plots[0,:], sharex=ax)  # clouds
   ax1 = fig.add_subplot(gs_cbar[2,:])              # colorbar


   bbox_barbs = dict(spacing=0.25, emptybarb=0.2, width=0.5, height=0.5)
   thermal_color = np.array([255,127,0])/255
   rain_color = np.array([154,224,228])/255
   terrain_color = np.array([158,65,12])/255

   msg =  f'({lat:.3f},{lon:.3f})'
   ax0.text(0, 1, msg, va='top', ha='left', color='k', fontsize=12,
                    bbox=dict(boxstyle="round", ec=None, fc=(1., 1., 1.,  .9)),
             zorder=100, transform=ax0.transAxes)

   ########### Central plot. Meteogram
   # LAYER 0. wspd contourf with padded time and transposed wspd
   # Create padding
   # Create two new times: one before, one after
   t_before = times[0] - np.timedelta64(mean_dt, 'm')
   t_after  = times[-1] + np.timedelta64(mean_dt, 'm')

   # Pad time axis
   times_padded = np.concatenate([[t_before], times, [t_after]])

   wspd_padded = pad_array(wspd).T
   heights_padded = pad_array(heights)
   umet_padded = pad_array(umet)
   vmet_padded = pad_array(vmet)
   heights_padded_mean = np.mean(heights_padded, axis=0)

   cf = ax.contourf(times_padded, heights_padded_mean, wspd_padded,
                    levels=range(0,60,4), vmin=0, vmax=60,
                    cmap=mcmaps.WindSpeed, extend='max',alpha=.7,zorder=0)
   # Colorbar
   ax1.grid(False)
   cbar = fig.colorbar(cf, cax=ax1, orientation="horizontal")
   cbar.set_label('km/h')

   # Label wind at hglider
   for x,y,h,t in zip(hours,hglider,heights,wspd):
      if y-GND < 100 : continue
      ax.text(x,y+15, f"{t[ np.argmin(np.abs(y - h)) ].magnitude:.0f}km/h",
              backgroundcolor=(1,1,1,.5), ha='center', zorder=21) #XXX breaks z-order convention


   # LAYER 1. Thermals
   bar_width = get_bar_width(25)
   ax.bar(hours, hglider, width=bar_width, color=thermal_color, zorder=10)
   dx = np.timedelta64(14,'m')
   for x,y,t in zip(hours, hglider,wstar):
      if t <= 0.01: continue
      if y-GND < 100 : continue
      t = f"{t:.1f}m/s"
      ax.text(x-dx, y-50, t, ha='right', va='top',
              rotation='vertical',backgroundcolor=(1,1,1,.5),zorder=11)
   temp = pad_array(tc).T
   iso0 = ax.contour(times_padded, heights_padded_mean, 
                     temp, levels=[-100,0,100], colors='cyan', 
                     linewidths=3, zorder=12)
   ax.clabel(iso0, iso0.levels, fmt=lambda x: f"{x:.0f}°C")



   # LAYER 2. Wind vertical profile
   # Plot padded barbs
   times_flat = np.repeat(times_padded, heights_padded.shape[1])
   heights_flat = heights_padded.flatten()
   umet_flat = umet_padded.flatten()
   vmet_flat = vmet_padded.flatten()
   ax.barbs(times_flat, heights_flat, umet_flat, vmet_flat,
            length=5, sizes=bbox_barbs, color='black', zorder=20)


   # LAYER 3. ~~zsfclcl clouds~~
   #          overcast clouds
   bar_width = get_bar_width(60)
   # TODO Vectorize this, for the love of god!!
   overcast = []
   for x,y in zip(p, rh):
      overcast.append( dq.get_overcast(y) )
   overcast = np.array(overcast)
   # Pad the clouds for smooth edges
   overcast_padded = pad_array(overcast).T
   ocf = ax.contourf(times_padded, heights_padded_mean, overcast_padded,
                     cmap=mcmaps.greys, vmin=0, vmax=1,zorder=30)
   # XXX Let's make zblcl Obsolete!

   # LAYER 4. ~~zblcl clouds~~
   #          cumulus clouds
   # Calculate pacel profile
   bases, tops = [],[]
   for x,y,z,q in zip(p, t0c, td0,tc):
      parcel = mpcalc.parcel_profile(x, y, z)
      parcel = parcel.to('degC')
      lcl_p, lcl_t = mpcalc.lcl(x[0], y, z)
      lcl_t = lcl_t.to('degC')
      base, top = dq.get_cumulus_base_top(x,q,parcel,lcl_p, lcl_t)
      cu_base_p, _ = base
      cu_top_p, _ = top
      if cu_base_p is None:
         bases.append(-999 * units('m'))  # XXX fails if np.nan
         tops.append( -998 * units('m'))  #
      else:
         bases.append(p2m(cu_base_p).to('m'))
         if cu_top_p is None:
             cu_top_p = 50 * units.hPa
         tops.append(p2m(cu_top_p).to('m'))
   tops = [t-b for t,b in zip(tops,bases)]
   a=ax.bar(hours, tops, bottom=bases, width=get_bar_width(40),
                       color=(.3,.2,.2,.7), zorder=40)

   # LAYER 5. Rain
   if any(rain > .5):
      rain_scale = 100
      bar_width = get_bar_width(15)
      ax.bar(hours, terrain+rain*rain_scale, width=get_bar_width(15),
                                         color=rain_color, zorder=50)
      # rain 1mm scale
      ax.bar(hours[0], terrain+rain_scale, width=get_bar_width(15),
             color='none', edgecolor='black', zorder=59)
      ax.text(hours[0]-np.timedelta64(22, 'm'), GND+rain_scale, '1mm',
              rotation='vertical', ha='left', va='top', zorder=61) # XXX bad ordering


   # LAYER 6. Ground
   x_min, x_max = ax.get_xlim()
   ground_bottom = terrain[0]-2000
   ground_rect = Rectangle((x_min, ground_bottom),   # (x, y) of lower-left
                           x_max - x_min,            # width
                           GND - ground_bottom,      # height
                           color='saddlebrown', zorder=60)
   ax.add_patch(ground_rect)
   ax.text(.01,.01, f'GND: {int(terrain[0])}m',
           backgroundcolor=(1,1,1,.5), transform=ax.transAxes, zorder=100)


   # LAYER 7. Wind 10m above ground
   ax.barbs(hours, terrain-30, umet10, vmet10, pivot='middle', length=6,
            sizes=dict(spacing=0.3, emptybarb=0.2, width=0.5, height=0.5),
            color='r', lw=3,zorder=71)
   dx = np.timedelta64(10,'m')
   for x, y, w in zip(hours, terrain,wspd10):
      t = f"{w.magnitude:.0f}"
      ax.text(x+dx, y, t, c='r',
              # ha='left', va='top', rotation=-90,
              va='top',
              backgroundcolor=(1,1,1,.5), zorder=70)
   #XXX bad ordering!
   ymax = np.max([np.max(hglider) + 800, 3000])
   delta_gnd = (ymax-terrain[0])/10
   ax.text(hours[len(hours)//2],terrain[0]-delta_gnd/1.75, 'sfcwind (km/h)',
           ha='center',
           c='r', backgroundcolor=(1,1,1,.5), zorder=100)


   # Y-label
   ax.set_ylabel("Height (m)")


   # Plot settings
   ax.set_xlim(times[0] - np.timedelta64(20, 'm'),
               times[-1] + np.timedelta64(30, 'm'))
   ymin = terrain[0] - delta_gnd
   ax.set_ylim(ymin,ymax)
   ax.xaxis.set_major_locator(mdates.HourLocator(interval=1))
   ax.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M'))


   ########### Upper plot. Cloud fraction
   # Cloud fraction
   aux = [high_cloudfrac, mid_cloudfrac, low_cloudfrac]
   img_cloud_pct = np.stack(aux, axis=1)
   img_cloud_pct = img_cloud_pct.transpose()

   # Plot the cloud fraction
   ax0.imshow(img_cloud_pct, cmap='Greys',vmin=0,vmax=1, 
              extent=[x_min,x_max,0,2], aspect='auto')

   # # Clouds plot
   ax0.set_yticks([1/3,1,5/3])
   ax0.set_yticklabels(['low','mid','high'])
   plt.setp(ax0.get_xticklabels(), visible=False)
   ax0.set_ylabel('Cloud %')
   # Title
   if len(title) > 0:
      pass
   else:
      title = f"{date.strftime('%d/%m/%Y')}"
      if len(name) > 0:
         title = f'{name} {title}'
   ax0.set_title(title)


### SAVE ######################################################################
   fig.savefig(fout, format=ext, bbox_inches='tight', pad_inches=0.1, dpi=150)
   LG.info(f'saved {fout}')
   plt.close('all')


if __name__ == '__main__':
   fname = "meteogram_41.1_-3.6.nc"
   plot_meteogram(fname)
