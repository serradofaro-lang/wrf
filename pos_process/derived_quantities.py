#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import logging
LG = logging.getLogger(__name__)
LG.setLevel(logging.DEBUG)

import numpy as np
from metpy.units import units
import metpy.calc as mpcalc
from scipy.interpolate import interp1d 

# For debugging
from metpy.plots import SkewT

def fermi(x,x0,t=1):
   return 1/(np.exp((x-x0)/(t))+1)


def get_cumulus_base_top(p,tc,parcel,lcl_p, lcl_t):
   """
   Estimate the base and top of a cumulus cloud, if present, based on a
   sounding profile

   Parameters. Expected to keep metpy units
   ----------
   p : array-like Pressure profile (1D, decreasing), typically in hPa.
   tc : array-like
       Temperature profile (1D), in degrees Celsius.
   parcel : array-like
       Parcel temperature profile (1D), in degrees Celsius.
   lcl_p : float
       Pressure at the lifting condensation level (LCL), in hPa.
   lcl_t : float with units
       Temperature at the LCL, as a `pint.Quantity` with units of degrees Celsius.

   Returns
   -------
   (cu_base_p, cu_base_t) : tuple or (None, None)
       Pressure and temperature at the base of the cumulus cloud, or (None, None) if no cloud forms.

   (cu_top_p, cu_top_t) : tuple or (None, None)
       Pressure and temperature at the top of the cumulus cloud, or (None, None) if no cloud forms.

   Notes
   -----
   This function compares the environmental temperature at the LCL to the parcel temperature.
   If the parcel is warmer than the environment, it is buoyant and cumulus development is expected.

   ASCII Diagrams
   --------------
   1. **Cumulus Forming:**
      The parcel (P) is warmer than the environment (E) at LCL and intersects it again at the cloud top.

          T
          ↑
          |
       E  |      /
       n  |     /
       v  |    /  ← Parcel (buoyant)
          |   /
       LCL*---    ← Cumulus base
          |  \
          |   \
          |    \  ← Cumulus top (where profiles intersect again)
          +--------------→ Pressure

   2. **No Cumulus:**
      The parcel is cooler than or equal to the environment at LCL — no buoyancy, no cloud.

          T
          ↑
          |
       E  |      /
       n  |     /
       v  |    /
          |   /
       LCL*---   ← Not buoyant: no cloud
          |  /
          | /
          |/   ← Parcel cooler or neutral
          +--------------→ Pressure
   """
   ftc = interp1d(p,tc)
   max_p = max(p)
   if max_p < lcl_p:
      if lcl_p <= max_p + 20 * units.hPa:
          LG.debug(f'LCL slightly below model levels ({lcl_p:~P} > {max_p:~P}). Clamping to surface.')
          lcl_p = max_p
      else:
          msg =  f'LCL bellow model levels. Non physical situation\n'
          msg += f'LCL: {lcl_p} || Lowest level (max P): {max_p}'
          LG.critical(msg)
          return (None, None), (None, None)
   
   if True: # Indentation level matching original 'else' block content

      if ftc(lcl_p) * tc.units < lcl_t: # cumulus
         LG.info('Cumulus expected')
         cu_base_p, cu_base_t = lcl_p, lcl_t
         inter_p,inter_t = mpcalc.find_intersections(p, tc,parcel, log_x=True)
         try:
            cu_top_p, cu_top_t = inter_p[0], inter_t[0]
            LG.debug(f'Cumulus base: {cu_base_p:.1f}, {cu_base_t:.1f}')
            LG.debug(f'Cumulus top: {cu_top_p:.1f}, {cu_top_t:.1f}')
         except:
            msg = 'No intersection found above LCL; cumulus top undefined'
            LG.debug(msg)
            cu_top_p, cu_top_t = None, None
      else: # no cumulus
         LG.debug('No Cumulus: Parcel not buoyant at LCL')
         cu_base_p, cu_base_t = None, None
         cu_top_p, cu_top_t = None, None
   return (cu_base_p, cu_base_t), (cu_top_p, cu_top_t)


def vertical_profile(N):
   """
   future modelling of the dependence of different kinds of clouds with
   the relative humidity at different levels
   """
   x0 = np.logspace(np.log10(.2),np.log10(7),N)
   t  = np.logspace(np.log10(.15),np.log10( 2),N)
   return x0, t


def find_cross(profile,tc,p,Ninterp=500):
   """
   Inputs should be arrays WITHOUT UNITS. Crossing is calculated via Bolzano:
   dif = tc-profile
   dif_norm = dif/|dif|  #only contains -1 or 1
   index of first +1 is the crossing point
   finds the lowest (highest p) crossing point between profile and tc curves
   Ninterp: [int] Number of interpolation points for the arrays.
            If Ninterp = 0 no interpolation is used
   """
   if Ninterp > 0:
      LG.debug('Interpolating with {Ninterp} points')
      ps = np.linspace(np.max(p),np.min(p),Ninterp)
      profile = interp1d(p,profile)(ps) #* profile.units
      tc = interp1d(p,tc)(ps) #* tc.units
      p = ps
   aux = profile-tc
   aux = (np.diff(aux/np.abs(aux)) != 0)*1   # manual implementation of sign
   ind, = np.where(aux==1)
   try: ind_cross = np.min(ind)
   except ValueError:
      LG.warning('Unable to find crossing point')
      ind_cross = 0
   p_base = p[ind_cross]
   t_base = tc[ind_cross]
   return p_base, t_base


#def get_cloud_base(parcel_profile,p,tc,lcl_p=None,lcl_t=None):
#   """
#   requires and keeps pint.units
#   returns the crossing of the parcel profile with the Tc
#   """
#   #XXX when I made this function, only god and me understood how it worked
#   # now only god knows
#   LG.debug('Find cloud base')
#   # Plot cloud base
#   print('**')
#   print(mpcalc.find_intersections(p, tc, parcel_profile, direction='all', log_x=True))
#   p_base, t_base = find_cross(parcel_profile, tc, p)
#   print('**')
#   if type(lcl_p) != type(None) and type(lcl_t) != type(None):
#      t_base = t_base * lcl_t.units
#      LG.debug(f'LCL is provided, using min(lcl,cu_base)')
#      print('-->',[lcl_p.magnitude, p_base.magnitude])
#      #XXX error in old code?!?!
#      p_base = np.min([lcl_p.magnitude, p_base.magnitude]) * lcl_p.units
#      t_base = np.min([lcl_t.magnitude, t_base.magnitude]) * lcl_t.units
#   return p_base, t_base


def get_cloud_extension(p,tc,td,rh, cu_base,cu_top, threshold=.3, width=.2, N=0):
   """
   Calculate the extension of the clouds. Two kinds.
     - overcast: we'll consider overcast clouds wherever tc-td < threshold
                 (there's some smoothing controlled by width to account for our
                 uncertainty).
     - cumulus: we'll consider cumulus clouds between cu_base and cu_top
   Returns 3 arrays with size (N,)
   ps: pressure levels for clouds
   overcast: proportional to non-convective cloud probability at every level
   cumulus: binary array with 1s where there are cumulus and 0s elsewhere
   """
   ## Clouds ############
   if N > 0:
      ps = np.linspace(np.max(p),np.min(p),N)
      tcs = interp1d(p,tc)(ps) * tc.units
      tds = interp1d(p,td)(ps) * td.units
   else:
      N = len(p)
      ps = p
      tcs = tc
      tds = td
   overcast = get_overcast(rh)
   # tdif = (tcs-tds).magnitude   # T-Td, proportional to Relative Humidity
   # x0, t =  vertical_profile(N)
   # overcast = fermi(tdif, x0=x0,t=t)
   # overcast = overcast/fermi(0, x0=x0,t=t)
   if any(v is None for v in (cu_base, cu_top)):
      cumulus = ps.magnitude * 0.
   else:
      cumulus = np.where((cu_base>ps) & (ps>cu_top),1,0)
   return ps, overcast, cumulus


def get_cumulus(ps,cu_base, cu_top):
   """
   returns an array with 0 where there is no cumulus clouds and 1 where there
   is
   The size is controlled by ps
   """
   if any(v is None for v in (cu_base, cu_top)):
      cumulus = ps.magnitude * 0.
   else:
      cumulus = np.where((cu_base>ps) & (ps>cu_top),1,0)
   return cumulus

def get_overcast(rh):
   """
   returns an array with 0 where there is no overcast clouds and 1 where there
   is
   The size is controlled by rh
   """
   def rh_log_threshold(nz, rh_top=0.9, rh_bottom=1):
      """Create a log-scaled RH threshold profile."""
      levels = np.arange(nz)
      log_scaled = np.log1p(levels) / np.log1p(levels[-1])
      return rh_top + (rh_bottom - rh_top) * (1 - log_scaled)
   def rh_to_cloud_prob(rh, threshold=0.95, slope=30):
      """
      Maps RH to a 0–1 probability with a sharp transition near the threshold
      """
      return 1 / (1 + np.exp(-slope * (rh - threshold)))
   nz = rh.shape[0]
   th_log = rh_log_threshold(nz)
   overcast = rh_to_cloud_prob(rh, th_log, slope=60)
   return overcast
