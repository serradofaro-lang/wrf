#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import log_help
import logging
LG = logging.getLogger(f'main.{__name__}')
LGp = logging.getLogger(f'perform.{__name__}')

import os
here = os.path.dirname(os.path.realpath(__file__))
HOME = os.getenv('HOME')

import sys
import subprocess
import glob
import sysconfig

def get_expected_so_name(module_name):
    """
    Returns the expected shared object name for the current python environment.
    e.g., drjack_num.cpython-310-x86_64-linux-gnu.so
    """
    suffix = sysconfig.get_config_var('EXT_SUFFIX')
    if not suffix:
        # Fallback for some systems
        suffix = ".so"
    return f"{module_name}{suffix}"

def recompile(f90_filename):
   """
   Compiles the f90 file using numpy.f2py if:
    1. The .so file is missing
    2. The source file (.f90) has changed (checked via diff with a cache file)
   """
   # Resolve full paths relative to this script location
   f90_path = os.path.join(here, f90_filename)
   module_name = f90_filename.replace('.f90', '')
   so_name = get_expected_so_name(module_name)
   so_path = os.path.join(here, so_name)
   cache_path = os.path.join(here, f".{f90_filename}")
   
   # Check if source changed
   source_changed = True
   if os.path.exists(cache_path):
       try:
           # If diff returns non-zero, files differ
           subprocess.check_call(['diff', '-q', f90_path, cache_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
           source_changed = False
       except subprocess.CalledProcessError:
           source_changed = True
   
   # Check if SO exists
   so_exists = os.path.exists(so_path)
   
   if source_changed or not so_exists:
       LG.warning(f'Compiling {f90_filename} (Source changed: {source_changed}, SO missing: {not so_exists})')
       
       # Build command: python3 -m numpy.f2py -c -m <module> <source>
       # Execute in 'here' directory so f2py finds the file and outputs .so there
       cmd = [sys.executable, '-m', 'numpy.f2py', '-c', '-m', module_name, f90_filename]
       
       try:
           subprocess.check_output(cmd, cwd=here, stderr=subprocess.STDOUT, text=True)
           LG.info(f"Compilation successful: {so_name}")
           # Update cache file
           subprocess.check_call(['cp', f90_path, cache_path])
       except subprocess.CalledProcessError as e:
           LG.critical(f"Compilation failed!\nCommand: {' '.join(cmd)}\nOutput:\n{e.output}")
           raise RuntimeError(f"Failed to compile {f90_filename}") from e
   else:
       LG.debug('Already compiled and up to date.')

recompile('drjack_num.f90')
try: 
    import drjack_num
except ImportError:
    # Double check if maybe the name is slightly different or something else went wrong
    LG.critical("Failed to import drjack_num even after attempted compilation.")
    raise
import numpy as np

from time import time


import numpy as np
# import functools
from functools import wraps
import xarray as xr

def wrap_as_xarray(array, reference, name=None, description=None, units=None, fill_value=None, extra_attrs=None):
    """
    Wrap a NumPy array into an xarray.DataArray using metadata from a reference DataArray.

    Parameters:
        array (np.ndarray): The new data to wrap.
        reference (xr.DataArray): Reference DataArray to inherit metadata (dims, coords, scalar coords, attrs).
        name (str): Optional name for the new DataArray.
        description (str): Description of the variable.
        units (str): Units of the variable.
        fill_value (float): Value to use for missing data. Also sets _FillValue and missing_value attributes.
        extra_attrs (dict): Additional attributes to attach.

    Returns:
        xr.DataArray: A new xarray object with metadata.
    """
    if not isinstance(reference, xr.DataArray):
        raise TypeError("Reference must be an xarray.DataArray")

    dims = reference.dims[:array.ndim]

    # Collect all coords matching the dimensions
    coords = {dim: reference.coords[dim] for dim in dims if dim in reference.coords}

    # Also include scalar coords (e.g. Time, XTIME)
    for k, v in reference.coords.items():
        if v.dims == ():
            coords[k] = v

    attrs = reference.attrs.copy()
    if description:
        attrs["description"] = description
    if units:
        attrs["units"] = units
    if fill_value is not None:
        attrs["_FillValue"] = fill_value
        attrs["missing_value"] = fill_value
        array = np.where(np.isnan(array), fill_value, array)
    if extra_attrs:
        attrs.update(extra_attrs)

    return xr.DataArray(array, dims=dims, coords=coords, name=name, attrs=attrs)


def maskPot0(M, terrain,bldepth,nan=-9999):
   """
   Masks values above the boundary layer by replacing them with a specified
   fill value.

   Parameters
   ----------
   M: [ndarray] Any 3D array, expected shape (nz, ny, nx)
   terrain: [ndarray] 2D array of surface elevation (ny, nx)
   bldepth: [ndarray] 2D array of boundary layer depth (ny, nx) in meters above
                      ground level
   nan: [float], optional. Fill value to use where M is outside the boundary
                 layer (default is -9999).

   Returns
   -------
   [ndarray] A masked version of M where values above the boundary layer are
             replaced with `nan`.
   """
   Mdif = terrain + bldepth - M
   null = 0. * M + nan
   return np.where( Mdif>0, M, null )

def calc_blavg(M, heights, terrain, bldepth):
   """
   * input must NOT be transposed form the wrf direct extraction
   Calculate the boundary-layer average of a variable using height-based
   integration.

   This function computes the vertical average of a 3D field within the boundary
   layer, defined from the surface to `terrain + pblh`, using height-based
   (z-level) interpolation
   The integration accounts for the actual height of the boundary layer top by
   linearly interpolating between model levels when needed.

   The average is calculated using the trapezoidal rule based on
   grid-point-to-grid-point depth, starting from the bottom model level
   The surface value is avoided by starting the first layer at half the depth
   between the terrain and the first model level, which reduces the influence of
   the often poorly-resolved surface layer.

   Parameters
   ----------
   M: [ndarray] (nz, ny, nx) 3D input field defined at mass (z) levels to be
      averaged
   heights: [ndarray] (nz, ny, nx) Height of each model level in meters
            (same shape as `M`)
   terrain: [ndarray] (ny, nx) Terrain height in meters
   bldepth: [ndarray] (ny, nx) Boundary layer height above ground level in meters

   Returns
   -------
    [ndarray] (ny, nx) 2D field of the boundary-layer-averaged variable.

   Notes
   -----
   - Linear interpolation is used to extend the average to the exact BL top
     if it falls between model levels.
   - This method avoids requiring a surface-layer value, which may be undefined
     or unrepresentative.
   - Assumes that all inputs are physically consistent and sorted vertically
     (i.e., `z` increases with the first index).

   """
   A = drjack_num.calc_blavg(M.transpose(), heights.transpose(),
                             terrain.transpose(), bldepth.transpose())
   return A



def calc_wblmaxmin(linfo, wa, heights, terrain, bldepth):
   """
   Wrapper for DrJack's transposes
   """
   wblmaxmin = drjack_num.calc_wblmaxmin(linfo, wa.transpose(),
                                         heights.transpose(),
                                         terrain.transpose(),
                                         bldepth.transpose())
   wblmaxmin = wrap_as_xarray(wblmaxmin.transpose(), terrain, name="wblmaxmin",
                     description="Maximum up/down-draft in the BL", units='m/s')
   return wblmaxmin


def calc_wstar(hfx,bldepth):
   wstar = drjack_num.calc_wstar(hfx.transpose(),bldepth.transpose())
   wstar = wrap_as_xarray(wstar.transpose(), hfx, name="wstar",
                           description="Convective velocity scale", units='m/s')
   return wstar


def calc_hcrit(wstar, terrain, bldepth, w_crit=1.143):
   LG.info('Calculating hcrit')
   w_crit_fpm = w_crit * 225/1.143
   hcrit_function = drjack_num.calc_hcrit
   hcrit = drjack_num.calc_hcrit( wstar.transpose(), terrain.transpose(),
                                  bldepth.transpose(),w_crit_fpm )
   hcrit = wrap_as_xarray(hcrit.transpose(), wstar, name="hcrit",
                                 description="Critical climb height", units='m')
   return hcrit


def calc_sfclclheight( pressure, tc, td, heights, terrain, bldepth):
   LG.info('Calculating sfclclheight')
   # Cu Cloudbase ~I~where Cu Potential > 0~P~
   zsfclcl = drjack_num.calc_sfclclheight( pressure.transpose(),
                                       tc.transpose(), td.transpose(),
                                       heights.transpose(),
                                       terrain.transpose(),
                                       bldepth.transpose() )
   zsfclcl = zsfclcl.transpose()
   zsfclcl = maskPot0(zsfclcl, terrain,bldepth)
   zsfclcl = wrap_as_xarray(zsfclcl, bldepth, name="zsfclcl",
                 description="Surface-based lifted condensation level height",
                 units='m', fill_value=-999)
   return zsfclcl


def calc_blclheight(qvapor,heights,terrain,bldepth,pmb,tc):
   LG.info('Calculating blclheight')
   qvaporblavg = calc_blavg( qvapor, heights, terrain, bldepth)
   heightsT = heights.transpose()
   terrainT = terrain.transpose()
   bldepthT = bldepth.transpose()
   pmbT = pmb.transpose()
   tcT = tc.transpose()
   zblcl = drjack_num.calc_blclheight(pmbT, tcT, qvaporblavg, heightsT, terrainT,
                                      bldepthT)
   zblcl = zblcl.transpose() #XXX Why this is not transpose?!
   zblcl = maskPot0(zblcl, terrain,bldepth)
   zblcl = wrap_as_xarray(zblcl, bldepth, name="zblcl",
                 description="BL-averaged lifted condensation level height",
                 units='m', fill_value=-999)
   return zblcl


def calc_hglider(hcrit,zsfclcl,zblcl):
   LG.info('Calculating hglider')
   hglider = np.maximum(np.minimum(zblcl, zsfclcl), hcrit)
   hglider = wrap_as_xarray(hglider, hcrit, name="hglider",
                 description="Glider-usable thermal height estimate (m)",
                 units='m', fill_value=-999)
   return hglider

def calc_wind_blavg(wind, heights, terrain, bldepth,name='', description=''):
   LG.info('Calculating wind_blavg')
   blavgwind = calc_blavg(wind, heights, terrain, bldepth)
   blavgwind = wrap_as_xarray(blavgwind.transpose(), terrain, name=name,
                 description=description,
                 units='m/s')
   return blavgwind

def calc_bltopwind(uEW,vNS,heights,terrain,bldepth):
   LG.info('Calculating bltopwind')
   utop,vtop = drjack_num.calc_bltopwind(uEW.transpose(),
                                         vNS.transpose(),
                                         heights.transpose(),
                                         terrain.transpose(),
                                         bldepth.transpose())
   utop = wrap_as_xarray(utop.transpose(), uEW,
                         name='umet', description='earth rotated u')
   vtop = wrap_as_xarray(vtop.transpose(), vNS,
                         name='vmet', description='earth rotated v')
   # , name="zbl",
   #               description="BL-averaged lifted condensation level height",
   #               units='m', fill_value=-999)
   return utop, vtop


def calc_Wspeed(u,v,name='',description=''):
   LG.info('Calculating Wspeed')
   wspd = np.sqrt( np.square(u) + np.square(v) )
   wspd = wrap_as_xarray(wspd, u, name=name, description=description)
   return wspd
