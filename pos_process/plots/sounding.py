#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import os
here = os.path.dirname(os.path.realpath(__file__))
HOME = os.getenv('HOME')
STYLE_PATH = os.path.join(here, "styles", "RASP.mplstyle")

import log_help
import logging
LG = logging.getLogger(f'main.{__name__}')
LGp = logging.getLogger(f'perform.{__name__}')

import matplotlib as mpl
mpl.use('Agg')

import wrf
import datetime as dt
import numpy as np
import matplotlib.pyplot as plt
plt.style.use(STYLE_PATH)
inter_axis_color = (.7,.7,.7)
from matplotlib import gridspec
from matplotlib.ticker import MultipleLocator
from . import colormaps as mcmaps

# Sounding
from metpy.plots import SkewT, Hodograph
from metpy.units import units
import metpy.calc as mpcalc
from scipy.interpolate import interp1d
import derived_quantities as dq
from . import utils as ut

p2m = mpcalc.pressure_to_height_std
m2p = mpcalc.height_to_pressure_std

UTCshift = dt.datetime.now() - dt.datetime.utcnow()
UTCshift = dt.timedelta(hours = round(UTCshift.total_seconds()/3600))

def interpolate_vars(p,tc,tdc,rh,u,v,Ninterp=250):
   LG.debug(f'Interpolating sounding variables to {Ninterp} levels')
   ps = np.linspace(np.max(p),np.min(p), Ninterp)
   ftc = interp1d(p,tc)
   ftdc = interp1d(p,tdc)
   frh = interp1d(p,rh)
   fu = interp1d(p,u)
   fv = interp1d(p,v)
   p = ps
   tc = ftc(ps) * tc.units
   rh = frh(ps)
   tdc = ftdc(ps) * tdc.units
   u = fu(ps) * u.units
   v = fv(ps) * v.units
   return p,tc,tdc,rh,u,v

def get_breaking_pressures(p, Pmin=150*units('hPa'), Pmed=500*units('hPa'),\
                                                     Pmax=1000*units('hPa')):
   """
   returns the indices in the provided p closest to Pmin,Pmed,Pmax
   used to break scale in th Y axis
   """
   n_min = np.argmin(np.abs(p-Pmin))
   n_med = np.argmin(np.abs(p-Pmed))
   n_max = np.argmin(np.abs(p-Pmax))
   return n_min, n_med, n_max

def get_bottom_temp(ax,T,P):
   """
   Returns the temperature in the X axis of any point in the skew-T graph
   """
   # Lower axis
   x0,x1 = ax.get_xlim()
   y0,y1 = ax.get_ylim()
   X0,X1 = ax.upper_xlim
   # Upper axis
   H = (x0-X0)/np.tan(np.radians(ax.rot))
   DX = x0-X0
   hp = H*(P.magnitude-y0)/(y1-y0)
   dx = hp*DX/H
   return T.magnitude+dx

   # LG.info('Adjusting X axis limits bottom sounding')
def center_x_data(ax,p,tc0,td0,Tmed,TDmed,Pmed):
   """
   For a fixed rotation of the skew-axis find the xmin,xmax that center
   all T,Td at ymax and 1st model level --> p[0]
   """
   difmin, difmax = 1000,1000
   tmin_old, tmax_old = ax.get_xlim()
   cont = 0
   while cont < 30 and not (difmin < .5 and difmax < .5):
      tmin = np.min([get_bottom_temp(ax,TDmed,Pmed),
                     get_bottom_temp(ax,td0,p[0])])
      tmax = np.max([get_bottom_temp(ax,Tmed,Pmed),
                     get_bottom_temp(ax,tc0,p[0])])
      tmin -= 10   # fine tune
      tmax += 10   #
      difmin = abs(tmin - tmin_old)
      difmax = abs(tmax - tmax_old)
      ax.set_xlim(tmin,tmax)
      LG.debug(f'T range: {tmin:.0f} - {tmax:.0f}')
      tmin_old = tmin
      tmax_old = tmax
      cont += 1
   LG.info(f'xlim adjusted to {tmin:.0f}-{tmax:.0f} after {cont} iterations')
   return tmin,tmax

def find_rotation(fig,subplot,t_top_min, t_top_max,p,tc,tdc,parcel,Pmed,Pmin,TDmin,Tmin):
   """
   The xmin,xman are fixed by the bottom graph, so we fit the data by adjusting
   the rotation of the axis iteratively until the lower and upper points (of
   this section) fit in the graph
   """
   isin = False  # Both Td and T are within the drawn limits
   rotation = 75
   rot_1 = rotation   # 1 step behind
   rot_2 = rotation   # 2 steps behind
   sign = 1
   delta_rot = 1
   i = 0
   LG.info('Adjusting rotation for top sounding')
   skew = SkewT(fig, rotation=rotation, subplot=subplot, aspect='auto')
   while not isin and i<21:   # XXX this is not technically guaranteed to work
                              # but it should be fine most of the time
      try: skew.ax.remove()
      except UnboundLocalError: pass
      rotation += sign*delta_rot
      if rotation == rot_1 or rotation == rot_2:
         delta_rot *= 0.9
      LG.debug(f'Trying skewness: {rotation:.0f}')
      skew = SkewT(fig, rotation=rotation, subplot=subplot, aspect='auto')
 
      # Plot Data to fit
      ## T and Tdew vs pressure
      skew.plot(p, tc,  'C3')
      skew.plot(p, tdc, 'C0')
      ## Parcel profile
      skew.plot(p, parcel, 'k', linewidth=1)

      ## Setup axis
      skew.ax.set_ylim(Pmed, Pmin)
      skew.ax.set_xlim(t_top_min, t_top_max)

      T0,T1 = skew.ax.upper_xlim
      isin = (T0 <= TDmin.magnitude <= Tmin.magnitude <= T1)
      # LG.debug(f'Upper data is visible: {isin}')
      sign = T0-TDmin.magnitude
      sign /= abs(sign)
      i+= 1
      rot_2 = rot_1
      rot_1 = rotation
   LG.info(f'Top sounding rotation decided: {rotation} after {i} iterations')
   return skew

@log_help.timer(LG, LGp)
def skew_t_plot(WRF, lat,lon, fout='sounding.png', title='', name='', interpolate=True, rot=30):
   """
   Layout             ________________________
                 Pmin|                 |C|Hod |<-- ax_hod
   ax1=skew_top.ax-->|_________________|L|____|
                 Pmed|                 |O|  I |
                 Pmed|                 |U|  N |
                     |                 |D|W T |
                     |                 |S|I E |
                     |    SOUNDING     | |N N |
                     |                 | |D S |
                     |                 | |  I |
                     |                 | |  T |
                 Pmax|_________________|_|__Y_|
                       ^                ^    ^
                ax0=skew_bot.ax  ax_clouds  ax_wind

   WRF: [calcdata.CalcData] ncprocessed file with variables extracted accesible
        via two dictionaries WRF.wrf_vars and WRF.drjack_vars
        Required properties:
         - Total pressure [hPa]: WRF.wrf_vars['p']
         - Vertical temperature [°C]: WRF.wrf_vars['tc']
         - Vertical dew temperature [°C]: WRF.wrf_vars['td']
         - 2m temperatire: WRF.wrf_vars['t2m']
         - 2m dew temperature [°C]: WRF.wrf_vars['td2m']
         - relative humidity [%]:  WRF.wrf_vars['rh']
         - Valid date of the forecast [datetime]: WRF.date
         - Vertical Earth-oriented wind u,v [m/s]: WRF.wrf_vars['uvmet']
         - Terrain [m (asl)]: WRF.wrf_vars['terrain']
   fout: [str] filename to save the plot
   title: [str] optional. Full title to use.
   name: [str] optional. If provided the title will be: "name d/m/Y-H:M"
   rot: [float] rotation of the Y axis for the main plot (temperature skewness)
   interpolate: [bool] Interpolate vertical levels for smoother graphs. Its
                main effect is visible in the wind intensity plot
   Aesthetics adapted from:
   https://geocat-examples.readthedocs.io/en/latest/gallery/Skew-T/NCL_skewt_3_2.html#sphx-glr-gallery-skew-t-ncl-skewt-3-2-py
   Notes
   - Respect MetPy's units throughout the script
   """
   LG.info(f'Starting Sounding for: {lat:.3f},{lon:.3f}')
   j,i = wrf.ll_to_xy(WRF.ncfile, lat, lon)
   lats = WRF.wrf_vars['lats']
   lons = WRF.wrf_vars['lons']
   lat = lats[i,j]
   lon = lons[i,j]
   LG.info(f'WRF closest point [{i.values},{j.values}]: {lat:.3f},{lon:.3f}')

   #                                       #
   #   Import and make MetPy units aware   #
   #                                       #
   ## Extract
   p       = WRF.wrf_vars['p'][:,i,j]
   tc      = WRF.wrf_vars['tc'][:,i,j]
   tdc     = WRF.wrf_vars['td'][:,i,j]
   t0      = WRF.wrf_vars['t2m'][i,j]
   td0     = WRF.wrf_vars['td2m'][i,j]
   rh      = WRF.wrf_vars['rh'][:,i,j]
   date    = WRF.meta['valid_time']
   u,v     = WRF.wrf_vars['uvmet']
   u = u[:,i,j]
   v = v[:,i,j]
   gnd     = WRF.wrf_vars['terrain'][i,j]
   ## MetPy units
   p       = p.values   * units(p.units)
   tc      = tc.values  * units(tc.units)
   tdc     = tdc.values * units(tdc.units)
   t0      = t0.values  * units(t0.units)
   td0     = td0.values * units(td0.units)
   u       = u.values   * units(u.units)
   v       = v.values   * units(v.units)
   gnd     = gnd.values * units(gnd.units)
   gnd_p   = m2p(gnd)   # ground in pressure units
   rh      = rh/100  #relative humidity 0-1
   ## Conversions
   t0c = t0.to('degC')
   u = u.to('km h-1')  
   v = v.to('km h-1')  
   ########################################

   # Interpolate data
   if interpolate:
      Npoints = 250
      LG.info(f'Interpolating data to {Npoints} vertical levels')
      p,tc,tdc,rh,u,v = interpolate_vars(p,tc,tdc,rh,u,v,Npoints)
   else: Npoints = len(p)
   # Get breaking pressure for vertical levels
   Pmin = 150*units('hPa')
   Pmed = 500*units('hPa')
   Pmax = 1000*units('hPa')
   n_min, n_med, n_max = get_breaking_pressures(p,Pmin,Pmed,Pmax)
   # Upper limit (min p)
   Pmin  = p[n_min]
   Tmin  = tc[n_min]
   TDmin = tdc[n_min]
   # Breaking scale point (med p)
   Pmed = p[n_med]
   Tmed = tc[n_med]
   TDmed = tdc[n_med]
   Pmax = 1000 * p.units  ############# lower limit unchanged
   LG.info(f'Breaking Y axis [{n_med}]: {Pmax:.0f}, {Pmed:.0f}, {Pmin:.0f}')

   #
   # Calculate pacel profile
   #
   parcel = mpcalc.parcel_profile(p, t0c, td0)
   lcl_p, lcl_t = mpcalc.lcl(p[0], t0c, td0)
   lcl_t = lcl_t.to('degC')
   # Find all intersections between parcel and T
   inter_p, inter_t = mpcalc.find_intersections(p, tc, parcel, log_x=True)
   if len(inter_p)>0:
      if lcl_p < inter_p[0]:
         techo = inter_p[0], inter_t[0]
      else:
         techo = lcl_p, lcl_t
   else:
      techo = np.nan*lcl_p.units, np.nan*lcl_t.units


   # Grid plot
   fig = plt.figure(figsize=(11, 13))
   gs = gridspec.GridSpec(2, 3, left=.11, right=.99, top=.99, bottom=.075,
                     height_ratios=[1,4.2], width_ratios=[6,0.5,1.8])
   fig.subplots_adjust(wspace=0.,hspace=0.)

   # Style for windbarbs
   bbox_hod_cardinal = dict(ec='none',fc='white', alpha=0.5)
   bbox_barbs = dict(emptybarb=0.075, width=0.1, height=0.2)
   xloc = 0.95

## BOTTOM PLOTS ###############################################################
#### Main Plot
   LG.info('Starting main plot')
   # Bottom left plot with the main sounding zoomed in to lower levels.
   skew_bot = SkewT(fig, rotation=rot, subplot=gs[1,0], aspect='auto')

   # Plot Data
   ## T, Tdew and parcel vs pressure
   skew_bot.plot(p, tc,  'C3')
   skew_bot.plot(p, tdc, 'C0')
   skew_bot.plot(p[0], td0, 'C0o')
   skew_bot.plot(p[0], t0c, 'C3o', zorder=100)
   skew_bot.plot(p, parcel, 'k', linewidth=1)
   skew_bot.plot(lcl_p, lcl_t, 'k.')
   skew_bot.shade_cape(p, tc, parcel)
   skew_bot.shade_cin(p, tc, parcel, tdc)
   # techo
   if not np.isnan(techo[0]):
       skew_bot.ax.axhline(techo[0], color=(0.5,0.5,0.5), ls='--')
       skew_bot.plot(techo[0], techo[1], 'k.')
       skew_bot.ax.text(techo[1], techo[0], f"{p2m(techo[0]).to('m'):.0f~P}")
   ## Windbarbs
   n = Npoints//50
   inds, = np.where(p>Pmed)
   inds = inds[::n]
   skew_bot.plot_barbs(pressure=p[inds], u=u[inds], v=v[inds],
                       xloc=xloc, sizes=bbox_barbs)
   # Guide lines
   X = np.array([p[0].magnitude,lcl_p.magnitude]) * lcl_p.units
   Y = np.array([td0.magnitude, lcl_t.magnitude]) * lcl_t.units
   skew_bot.plot(X, Y, color='C2',ls='--',lw=1.5, zorder=0)
   ## Iso 0 & -10
   skew_bot.ax.axvline(0, color='cyan',lw=0.65)
   skew_bot.ax.axvline(-10, color='cyan',ls='--',lw=0.5)
   ## Iso t0
   skew_bot.plot([Pmax.magnitude,p[0].magnitude],
                 [t0c.magnitude,t0c.magnitude],
                 color=(0.5,0.5,0.5),ls='--')
   skew_bot.ax.text(t0c,Pmax,f'{t0c:.1f~P}',va='bottom',ha='left')

   ## Dry Adiabats
   t_dry = np.arange(-30, 200, 10) * units('degC')
   skew_bot.plot_dry_adiabats(t0=t_dry, linestyles='solid', colors='gray',
                                    linewidth=1)
   ## Moist Adiabats
   t_moist = np.arange(8, 33, 4)  * units('degC') 
   msa = skew_bot.plot_moist_adiabats(t0=t_moist,
                                  linestyles='solid',
                                  colors='lime',
                                  linewidths=.75)
   ## Mixing Ratios
   w = np.array([0.001, 0.002, 0.003, 0.005, 0.008, 0.012, 0.020])
   w = w.reshape(-1, 1)
   # Vertical extension for the mixing ratio lines
   p_levs = np.linspace(1000, 650, 7) * units.hPa
   skew_bot.plot_mixing_lines(mixing_ratio=w, pressure=p_levs, colors='C2',
                              linestyle='--',linewidths=1)

   ## Setup axis
   # Y axis
   skew_bot.ax.set_ylim(Pmax, Pmed)
   # Change pressure labels to height
   yticks, ylabels = [],[]
   for x in reversed(np.arange(0,20000,500)):
      x = x*units.m
      px = m2p(x)
      if Pmax > px > Pmed:
         yticks.append(px)
         ylabels.append(f'{x:.0f~P}\n{px:.0f~P}')
   skew_bot.ax.set_yticks(yticks)
   skew_bot.ax.set_yticklabels(ylabels)
   skew_bot.ax.set_ylabel('Altitude in std atmosphere')
   # X axis
   # Find xlims iteratively since the aspect ratio has to be set to auto for
   # the scale break to work
   center_x_data(skew_bot.ax,p,max([t0c,tc[0]]),td0,Tmed,TDmed,Pmed)
   skew_bot.ax.set_xlabel('Temperature (°C)')
   # Xticks
   skew_bot.ax.xaxis.set_major_locator(MultipleLocator(5))
   ## Change the style of the gridlines
   skew_bot.ax.grid(True, which='major', axis='both',
            color='tan', linewidth=1.5, alpha=0.5)
   skew_bot.ax.spines['top'].set_color('none')
   LG.info('Done main plot')

### Clouds
   base, top = dq.get_cumulus_base_top(p,tc,parcel,lcl_p, lcl_t)
   cu_base_p, cu_base_t = base
   cu_top_p, cu_top_t = top
   cumulus = dq.get_cumulus(p,cu_base_p, cu_top_p)
   overcast = dq.get_overcast(rh)
   # Generate clouds image from p, overcast and cumulus
   rep = 6  # repeat the columns for a sharper transition between O and C
   mats =  [overcast for _ in range(rep)]
   mats += [cumulus for _ in range(rep)]
   cloud = np.vstack(mats).transpose()
   Xcloud = np.vstack([range(2*rep) for _ in range(cloud.shape[0])])
   Ycloud = np.vstack([p for _ in range(2*rep)]).transpose()
   # Plot clouds image
   LG.info('Plotting clouds bottom')
   ax_cloud_bot = plt.subplot(gs[1,1], sharey=skew_bot.ax, zorder=-1)
   ax_cloud_bot.contourf(Xcloud, Ycloud, cloud,
                         cmap=mcmaps.mygreys,vmin=0,vmax=1)
   for ix,txt in zip([.25,.75], ['O','C']):
      ax_cloud_bot.text(ix,0,txt,ha='center',va='bottom',
                                           transform=ax_cloud_bot.transAxes)
   plt.setp(ax_cloud_bot.get_xticklabels(), visible=False)
   plt.setp(ax_cloud_bot.get_yticklabels(), visible=False)
   ax_cloud_bot.set_ylabel('')
   ax_cloud_bot.grid(False)
   ax_cloud_bot.spines['top'].set_color('none')
   LG.info('Done clouds bottom')

### Wind Plot
   LG.info('Plotting wind bottom')
   ax_wind_bot  = plt.subplot(gs[1,2], sharey=skew_bot.ax)
   wspd = np.sqrt(u*u + v*v)
   ax_wind_bot.scatter(wspd, p, c=p, cmap=mcmaps.HEIGHTS, zorder=10)
   # X axis
   ax_wind_bot.set_xlim(0, 56)
   ax_wind_bot.set_xlabel('Wspeed (km/h)')
   ax_wind_bot.xaxis.set_major_locator(MultipleLocator(8))
   ax_wind_bot.xaxis.set_minor_locator(MultipleLocator(4))
   plt.setp(ax_wind_bot.get_yticklabels(), visible=False)
   ax_wind_bot.set_ylabel('')
   ax_wind_bot.grid(True, which='major', axis='x',color=(.8,.8,.8))
   ax_wind_bot.grid(True, which='minor', axis='x',color=(.5,.5,.5))
   LG.info('Done wind bottom')

### TOP PLOTS #########################################################
### Sounding upper levels
   t_top_min, t_top_max = skew_bot.ax.upper_xlim
   skew_top = find_rotation(fig,gs[0,0],t_top_min, t_top_max,
                 p[n_med:],tc[n_med:],tdc[n_med:],parcel[n_med:],
                 Pmed,Pmin,TDmin,Tmin)
   # find_rotation already plots tc, tdc and parcel
   skew_top.shade_cape(p, tc, parcel)
   skew_top.shade_cin(p, tc, parcel, tdc)
   LG.info('plotted CAPE and CIN')
   skew_top.ax.xaxis.set_major_locator(MultipleLocator(5))
   skew_top.ax.set_xlabel('')

   ## Windbarbs
   n = Npoints//20
   inds, = np.where((p<Pmed) & (p>Pmin))
   inds = inds[::n]
   skew_top.plot_barbs(pressure=p[inds], u=u[inds], v=v[inds],
                       xloc=xloc, sizes=bbox_barbs)
   ## Setup axis
   # Y axis
   # Change pressure labels to height
   yticks_top, ylabels = [],[]
   for x in np.arange(0,20000,1500):
      px = m2p(x*units.m)
      if Pmed > px > Pmin:
         yticks_top.append(px)
         ylabels.append(f'{x:.0f}')
   skew_top.ax.set_yticks(yticks_top)
   skew_top.ax.set_yticklabels(ylabels)
   skew_top.ax.set_ylabel('Altitude (m)')
   # Iso 0 & -10
   skew_top.ax.axvline(0, color='cyan',lw=0.65)
   skew_top.ax.axvline(-10, color='cyan',ls='--',lw=0.5)

   msg =  f'({lat:.3f},{lon:.3f})'
   msg += f"\nplot: {dt.datetime.now().strftime('%d/%m-%H:%M')}"
   skew_top.ax.text(0, 1, msg, va='top', ha='left', color='k', fontsize=12,
                    bbox=dict(boxstyle="round", ec=None, fc=(1., 1., 1.,  .9)),
             zorder=100, transform=skew_top.ax.transAxes)
   if len(title) > 0:
      pass
   else:
      title = f"{(date+UTCshift).strftime('%d/%m/%Y-%H:%M')}"
      if len(name) > 0:
         title = f'{name} {title}'
   skew_top.ax.set_title(title)

   # Change the style of the gridlines
   skew_top.ax.grid(True, which='major', axis='both', color='tan',
                                         linewidth=1.5, alpha=0.5)
   plt.setp(skew_top.ax.get_xticklabels(), visible=False)
   skew_top.ax.spines['bottom'].set_color(inter_axis_color)

### Clouds
   LG.info('Plotting clouds top')
   ax_cloud_top = plt.subplot(gs[0,1], sharey=skew_top.ax, zorder=-1)
   ax_cloud_top.contourf(Xcloud, Ycloud, cloud, cmap=mcmaps.mygreys)
   plt.setp(ax_cloud_top.get_xticklabels(), visible=False)
   plt.setp(ax_cloud_top.get_yticklabels(), visible=False)
   ax_cloud_top.set_ylabel('')
   ax_cloud_top.grid(False)
   ax_cloud_top.spines['bottom'].set_color(inter_axis_color)
   LG.info('Done clouds top')

### Wind Plot. Hodograph
   LG.info('Plotting hodograph')
   ax_wind_top  = plt.subplot(gs[0,2])
   ax_hod = ax_wind_top
   ax_hod.set_yticklabels([])
   ax_hod.set_xticklabels([])
   L = 80
   bbox = dict(ec='none',fc='white', alpha=0.5)
   ax_hod.text(  0, L-5,'N',  ha='center', va='top',    bbox=bbox_hod_cardinal)
   ax_hod.text(L-5,  0,'E',   ha='right',  va='center', bbox=bbox_hod_cardinal)
   ax_hod.text(-(L-5),0 ,'W', ha='left',   va='center', bbox=bbox_hod_cardinal)
   ax_hod.text(  0,-(L-5),'S',ha='center', va='bottom', bbox=bbox_hod_cardinal)
   h = Hodograph(ax_hod) #, component_range=L)
   h.add_grid(increment=20, lw=1, zorder=-1)
   # Plot a line colored by pressure (altitude)
   h.plot_colormapped(-u, -v, p, cmap=mcmaps.HEIGHTS)
   ax_hod.grid(False)
   LG.info('Done hodograph')
   LG.info('Done wind')

### COMMON ####################################################################
   # Ground
   skew_bot.ax.axhline(p[0].magnitude,c='k',ls='--')
   ax_cloud_bot.axhline(p[0].magnitude,c='k',ls='--')
   ax_wind_bot.axhline(p[0].magnitude,c='k',ls='--')
   trans, _, _ = skew_bot.ax.get_yaxis_text1_transform(0)
   ty = (p[0].magnitude+15)*p.units
   skew_bot.ax.text(0,ty,f'GND:{gnd:.0f~P}', transform=trans)

### SAVE ######################################################################
   LG.info('saving')
   fig.savefig(fout, format='webp',bbox_inches='tight', pad_inches=0.1, dpi=100)
   LG.info(f'saved {fout}')
   plt.close('all')
