#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import os
here = os.path.dirname(os.path.realpath(__file__))
HOME = os.getenv('HOME')
STYLE_PATH = os.path.join(here, "styles", "RASP.mplstyle")
import matplotlib as mpl
mpl.use('Agg')

import numpy as np
import pandas as pd
import datetime as dt
import metpy.calc as mpcalc
from metpy.units import units
import matplotlib.pyplot as plt
plt.style.use(STYLE_PATH)
import matplotlib.dates as mdates
import matplotlib.ticker as ticker
from . import utils as ut
# Night

# Removing astral dependency for night shading as we now use OWM data
# from astral import LocationInfo
# from astral.sun import sun


def night_shade(axs, start, end, sunrise=None, sunset=None):
   """
   Draw night shading on axes based on provided sunrise/sunset times.
   Shades background from:
     - start -> sunrise (morning twilight/night)
     - sunset -> end (evening twilight/night)
   """
   color = np.array([3, 28, 43, 100]) / 255
   
   # If we have valid sun times, apply shading
   if pd.notna(sunrise) and pd.notna(sunset):
       # Ensure they are timezone-aware or compatible with start/end (typically UTC-shifted)
       # OWM returns datetimes. Our 'start'/'end' are usually local-ish or aligned.
       # We assume sunrise/sunset passed here are already shifted/aligned to the plot axis.
       
       for ax in axs:
           # Shade morning: start to sunrise
           if start < sunrise:
              ax.axvspan(start, sunrise, color=color)
           
           # Shade evening: sunset to end
           if sunset < end:
              ax.axvspan(sunset, end, color=color)
              
       # Add text labels
       if len(axs) > 1:
          if start < sunrise < end:
             axs[1].text(sunrise, 0, 'Sunrise', rotation=90, verticalalignment='bottom')
          if start < sunset < end:
             axs[1].text(sunset, 0, 'Sunset', rotation=90, verticalalignment='bottom')





UTCshift = ut.utc_shift()

def rotate_wind(arr):
   return (arr+180) % 360

def compare(obs_df, wrf_df, title='',fout='baliza.png'):
   # Determine 'today' based on the last available data in WRF dataframe
   # This allows plotting historical data without filtering it out
   # Determine 'today' logic
   # Prioritize showing the current day if the data is recent (Nowcasting context)
   # Otherwise (historical analysis), show the last available day in WRF data.
   
   last_wrf_time = wrf_df.index[-1]
   now = dt.datetime.now()
   
   # If WRF data ends far in the past (> 2 days ago), assume historical re-run
   if (now - last_wrf_time).days > 2:
       today = last_wrf_time.replace(hour=0,minute=0,second=0,microsecond=0)
   else:
       # Default: Show TODAY (system time)
       today = now.replace(hour=0,minute=0,second=0,microsecond=0)
       
       # Special case: If WRF hasn't reached today yet (e.g. processing yesterday's run),
       # we might want to start there. 
       # But typically WRF goes into the future.
       # If today is NOT in wrf_df range (e.g. prediction ended yesterday), fallback to last_wrf.
       if today > last_wrf_time:
             today = last_wrf_time.replace(hour=0,minute=0,second=0,microsecond=0)
   
   start = today
   end   = start + dt.timedelta(days=1)
   
   # Filter logic remains similar but relative to the data's own timeline
   wrf_df = wrf_df[wrf_df.index >= today - UTCshift].copy()
   # skip first line (pure GFS data) ONLY if we have a sequence
   if len(wrf_df) > 1:
       wrf_df = wrf_df.iloc[1:].copy()
   wrf_df = wrf_df[wrf_df.index < end].copy()
   obs_df = obs_df[obs_df.index >= today - UTCshift].copy()


   for df in [wrf_df, obs_df]:
      df['wind_heading_north'] = df['wind_heading'].apply(rotate_wind)
   obs_DF = obs_df.resample("h", label='right', closed='right').mean()

   # Plots
   # Decide fields to plot
   n = 2     # at least always show wind
   include_temp  = obs_df['temperature'].notna().any()
   include_rh    = obs_df['rh'].notna().any()
   include_solar = obs_df['swdown'].notna().any()
   if include_temp:  n += 1
   if include_solar: n += 1
   fig, axes = plt.subplots(n, 1, figsize=(12,4*n), sharex=True,
                                  gridspec_kw={'hspace': 0})
   ax0 = axes[0]
   ax1 = axes[1]
   
   # Extract sunrise/sunset from observations if available
   # Since they are repeated in the CSV, we can take the first valid one
   # and apply UTC shift to match the plot axis
   sr_val, ss_val = None, None
   if 'sunrise' in obs_df.columns and 'sunset' in obs_df.columns:
       valid_sr = obs_df['sunrise'].dropna()
       valid_ss = obs_df['sunset'].dropna()
       if not valid_sr.empty:
           sr_val = valid_sr.iloc[0] + UTCshift
       if not valid_ss.empty:
           ss_val = valid_ss.iloc[0] + UTCshift

   night_shade(axes, start, end, sunrise=sr_val, sunset=ss_val)

   ## Wspd

   # station 5-minute
   x = (obs_df.index + UTCshift).values
   y = obs_df['wind_speed_avg'].values
   ymin = obs_df['wind_speed_min'].values
   ymax = obs_df['wind_speed_max'].values
   ylim_max = 0
   if len(ymax) > 0 and not np.isnan(ymax).all():
       ylim_max = np.nanmax(ymax)
   ax0.plot(x,y,'C0-.', label='Station full', alpha=.5)
   ax0.fill_between(x,ymin,ymax,color='C0',alpha=.3)
   # station 60-minute
   x = (obs_DF.index + UTCshift).values
   y = obs_DF['wind_speed_avg'].values
   if len(y) > 0 and not np.isnan(y).all():
       ylim_max = max(ylim_max, np.nanmax(y))
   ax0.plot(x,y,'C0-o', label='Station hourly')
   # WRF
   x = (wrf_df.index + UTCshift).values
   y = wrf_df['wind_speed_avg'].values
   if len(y) > 0 and not np.isnan(y).all():
       ylim_max = max(ylim_max, np.nanmax(y))
   ax0.plot(x,y,'C1-o', label='RASP')

   ax0.set_ylabel('Wspeed (km/h)')
   # ax.set_xlabel('Time')
   ax0.set_title(title)
   ax0.set_xticklabels([])
   if np.isnan(ylim_max): ylim_max = 30
   ax0.set_ylim(0, max([ylim_max, 30])+2.5) # XXX


   ## Wdir
   aux = np.concatenate([obs_DF['wind_heading'].values,wrf_df['wind_heading'].values])
   if len(aux) > 1:
       aux_diff = np.max(np.abs(np.diff(aux)))
       if aux_diff > 180:
          center_north = True
          center = 180
       else:
          center_north = False
          center = 0
   else:
       center_north = False
       center = 0

   if center_north: wdir_col = 'wind_heading_north'
   else: wdir_col = 'wind_heading'
   # station 5-minute
   x = (obs_df.index + UTCshift).values
   y = obs_df[wdir_col].values
   ax1.plot(x,y,'C0-.', label='Station full', alpha=.5)
   # station 60-minute
   x = (obs_DF.index + UTCshift).values
   y = obs_DF[wdir_col].values
   ax1.plot(x,y,'C0-o', label='Station hourly')
   # WRF
   x = (wrf_df.index + UTCshift).values
   y = wrf_df[wdir_col].values
   ax1.plot(x,y,'C1-o', label='RASP')

   # Rotation eye-guides
   ax1.axhline(center,ls='--',color='k')
   ax1.text(end,(center-17)%360,'North',ha='right')

   # Labels
   ax1.set_ylabel('Wdir (°)')
   cardinals_lbl = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW']
   d_alpha = 360/len(cardinals_lbl)
   cardinals_pos = [(i * d_alpha) % 360 for i in range(len(cardinals_lbl))]
   if center_north: cardinals_pos = [rotate_wind(i) for i in cardinals_pos]
   ax1.set_yticks(cardinals_pos)
   ax1.set_yticklabels(cardinals_lbl)
   ax1.set_ylim(0,360)
   ax1.legend()

   
   msg = dt.datetime.now().strftime('Actualizado: %H:%M %d/%m/%Y')
   props = dict(boxstyle='round', facecolor='white', alpha=0.9)
   ax1.text(1, .998, msg, transform=ax0.transAxes, va='top', ha='right', bbox=props)
   
   n_ax = 2  # after plotting wind, the next available axis is axes[n_ax]
   if include_temp:
      # Temperature
      ax2 = axes[n_ax]
      n_ax += 1  # increase counting for next plot
      ax2_twin = ax2.twinx()
      x = (obs_df.index + UTCshift).values
      y = obs_df['temperature'].values
      ax2.plot(x,y, 'C0-.', alpha=.5)
      x = (obs_DF.index + UTCshift).values
      y = obs_DF['temperature'].values
      ax2.plot(x,y, 'C0-o')
      x = (wrf_df.index + UTCshift).values
      y = wrf_df['temperature'].values
      ax2.plot(x,y, 'C1-o')

      if include_rh:
         # Relative humidity
         x = (obs_df.index + UTCshift).values
         y = obs_df['rh'].values
         ax2_twin.plot(x,y, 'C2-.', alpha=.5)
         x = (obs_DF.index + UTCshift).values
         y = obs_DF['rh'].values
         ax2_twin.plot(x,y, 'C2-o', label='Station Rh (%)')
         x = (wrf_df.index + UTCshift).values
         y = wrf_df['rh'].values
         ax2_twin.plot(x,y, 'C3-o', label='RASP Rh (%)')
         # Settings
         ax2.set_ylabel('Temperature (°C)')
         # ax2_twin.set_ylabel('Relative Humidity (%)')
         ax2_twin.legend(loc=2)
         ax2_twin.set_ylim(0,100)
   if include_solar:
      ax3 = axes[n_ax]
      n_ax += 1  # increase counting for next plot
      x = (obs_df.index + UTCshift).values
      y = obs_df['swdown'].values
      ax3.plot(x,y, 'C0-.', alpha=.5)
      x = (obs_DF.index + UTCshift).values
      y = obs_DF['swdown'].values
      ax3.plot(x,y, 'C0-o')
      x = (wrf_df.index + UTCshift).values
      y = wrf_df['swdown'].values
      ax3.plot(x,y, 'C1-o')
      # Settings
      ax3.set_ylabel('Solar ($W/m^2$)')

   # Grid and ticks
   for ax in axes:
      ax.grid(True)
      ax.xaxis.set_major_locator(mdates.HourLocator(interval=3))
      ax.xaxis.set_minor_locator(mdates.HourLocator(interval=1))
      # Grid lines ONLY for X-axis minor ticks
      ax.xaxis.grid(which='minor', linestyle=':', linewidth=.5, color='gray')
      ax.xaxis.grid(which='major', linestyle='-', linewidth=.5, color='gray')
      ax.set_xlim(start,end)
   axes[-1].xaxis.set_major_formatter(mdates.DateFormatter('%H:%M'))
   for label in ax1.get_xticklabels(which='major'):
      label.set(rotation=20, horizontalalignment='right')

   fig.tight_layout()
   fig.savefig(fout)
   
   # --- Generate comparison text file ---
   from pathlib import Path
   try:
      txt_out = Path(fout).with_suffix('.txt')
      
      # Join datasets on time index to align them
      # obs_DF is hourly mean, wrf_df is hourly model data
      common_df = obs_DF.join(wrf_df, lsuffix='_obs', rsuffix='_pred', how='inner')
      
      with open(txt_out, 'w') as f:
         f.write(f"Comparison Report: {title}\n")
         f.write(f"Generated: {dt.datetime.now()}\n")
         f.write("-" * 65 + "\n")
         f.write(f"{'Time':<20} | {'Var':<12} | {'Obs':<8} | {'Pred':<8} | {'Diff':<8}\n")
         f.write("-" * 65 + "\n")
         
         for time, row in common_df.iterrows():
             time_str = (time + UTCshift).strftime('%Y-%m-%d %H:%M')
             
             # Temperature
             if include_temp:
                 val_obs = row.get('temperature_obs', np.nan)
                 val_pred = row.get('temperature_pred', np.nan)
                 diff = val_pred - val_obs
                 f.write(f"{time_str:<20} | {'Temp':<12} | {val_obs:<8.2f} | {val_pred:<8.2f} | {diff:<8.2f}\n")

             # Wind Speed
             val_obs = row.get('wind_speed_avg_obs', np.nan)
             val_pred = row.get('wind_speed_avg_pred', np.nan)
             diff = val_pred - val_obs
             f.write(f"{time_str:<20} | {'WSpeed':<12} | {val_obs:<8.2f} | {val_pred:<8.2f} | {diff:<8.2f}\n")
             
             # Wind Dir
             val_obs = row.get('wind_heading_obs', np.nan)
             val_pred = row.get('wind_heading_pred', np.nan)
             diff = (val_pred - val_obs + 180) % 360 - 180
             f.write(f"{time_str:<20} | {'WDir':<12} | {val_obs:<8.0f} | {val_pred:<8.0f} | {diff:<8.0f}\n")
             
             if include_rh:
                 val_obs = row.get('rh_obs', np.nan)
                 val_pred = row.get('rh_pred', np.nan)
                 diff = val_pred - val_obs
                 f.write(f"{time_str:<20} | {'RH':<12} | {val_obs:<8.1f} | {val_pred:<8.1f} | {diff:<8.1f}\n")

             f.write("-" * 65 + "\n")
             
      # LG.info(f"Saved comparison text to {txt_out}")

   except Exception as e:
      print(f"Failed to generate comparison text: {e}")
 
