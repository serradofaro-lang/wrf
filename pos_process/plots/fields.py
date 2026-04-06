#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import log_help
import logging
LG = logging.getLogger(f'main.{__name__}')
LGp = logging.getLogger(f'perform.{__name__}')

import matplotlib as mpl
mpl.use('Agg')

import numpy as np
from . import colormaps as mcmaps
import matplotlib.pyplot as plt
from mpl_toolkits.axes_grid1 import make_axes_locatable
from matplotlib.colors import BoundaryNorm
from time import time



mycolormaps = {'WindSpeed': mcmaps.WindSpeed,
               'Convergencias': mcmaps.Convergencias,
               'CAPE': mcmaps.CAPE, 'Rain': mcmaps.Rain, 'None': None,
               'greys': mcmaps.greys, 'reds': mcmaps.reds,
               'greens': mcmaps.greens, 'blues': mcmaps.blues}

def compute_wrf_edges(X):
   """
   Given a 2D array of center coordinates X (either lons or lats),
   compute edges using central differences (averaging adjacent points).
   Resulting shape is (ny+1, nx+1)
   """
   ny, nx = X.shape
   X_edge = np.zeros((ny + 1, nx + 1))
   
   # Interior
   X_edge[1:-1, 1:-1] = (X[:-1, :-1] + X[1:, :-1] + X[:-1, 1:] + X[1:, 1:])/4
   
   # Edges: extrapolate
   X_edge[0, 1:-1]     = 2 * X[0, :-1] - X[1, :-1]
   X_edge[-1, 1:-1]    = 2 * X[-1, :-1] - X[-2, :-1]
   X_edge[1:-1, 0]     = 2 * X[:-1, 0] - X[:-1, 1]
   X_edge[1:-1, -1]    = 2 * X[:-1, -1] - X[:-1, -2]

   # Corners: extrapolate diagonally
   X_edge[0, 0]        = 2 * X[0, 0] - X[1, 1]
   X_edge[0, -1]       = 2 * X[0, -1] - X[1, -2]
   X_edge[-1, 0]       = 2 * X[-1, 0] - X[-2, 1]
   X_edge[-1, -1]      = 2 * X[-1, -1] - X[-2, -2]
   return X_edge



@log_help.timer(LG, LGp)
def scalar_plot(ax, crs_data, lons, lats, prop,
                delta, vmin, vmax, cmap,
                levels=None, inset_label='', prop_name=''):
   """
   Plot a scalar (2D) field using contourf on a geographic axis.

   Parameters
   ----------
   ax : matplotlib.axes._subplots.AxesSubplot
       The axes on which to plot.
   crs_data : cartopy.crs
       The CRS of the data (used in the `transform` argument).
   lons, lats : 2D ndarray
       Longitude and latitude meshgrids matching the data grid.
   prop : 2D ndarray
       The scalar field to be plotted.
   delta : float
       Step size between color levels if `levels` is computed automatically.
   vmin, vmax : float
       Minimum and maximum values for colormap normalization.
   cmap : str or colormap
       Name of the colormap (defined in `mycolormaps` or default matplotlib).
   levels : list[float] or None, optional
       Discrete contour levels. If None, they're computed from vmin to vmax.
       If an empty list, defaults to automatic linear spacing.
   inset_label : str, optional
       A label shown in the bottom-right corner of the plot (e.g. timestamp).
   prop_name : str, optional
       Name of the property being plotted (used in logs).

   Returns
   -------
   contourf : QuadContourSet or None
       The contourf handle for the colorbar, or None if plotting failed.
   """
   LG.debug(f'Plotting {prop_name}')

   if np.isnan(prop).all():
       LG.warning(f"Skipping plot for {prop_name}: Data is all NaN")
       return None

   try:
       msg = f'{prop_name} lims: {vmin}/{np.nanmin(prop):.1f}/{np.nanmax(prop):.1f}/{vmax}'
   except Exception as e:
       msg = f'Failed to compute min/max for {prop_name}: {e}'
   LG.debug(msg)


   if isinstance(cmap, str):
       if cmap in mycolormaps and mycolormaps[cmap] is not None:
           cmap = mycolormaps[cmap]
       else:
           try:
               cmap = plt.get_cmap(cmap)
           except Exception:
               cmap = plt.get_cmap("viridis")
   elif cmap is None:
       cmap = plt.get_cmap(None)

   # Plot the data
   lon_edges = compute_wrf_edges(lons)
   lat_edges = compute_wrf_edges(lats)
   prop_edges = compute_wrf_edges(prop)
   shade = 'gouraud'
   t0 = time()
   if np.isnan(delta):   # smooth gradient
      try: 
         ax.pcolormesh(lon_edges, lat_edges, prop_edges,
                       cmap=cmap,
                       vmin=vmin, vmax=vmax,
                       shading=shade, transform=crs_data,
                       antialiased=True
                       )
      except Exception as e:
         LG.warning(f"Failed pcolormesh for {prop_name}: {e}")
   else:
      if len(levels) == 0: levels = np.arange(vmin,vmax,delta)
      else: pass
      norm = BoundaryNorm(levels, cmap.N)
      try:
         ax.pcolormesh(lon_edges, lat_edges, prop_edges,
                       cmap=cmap, norm=norm,
                       # vmin=vmin, vmax=vmax,  # Optional if using norm
                       shading=shade, transform=crs_data,
                       antialiased=True
                       )
      except Exception as e:
         LG.warning(f"Failed to plot {prop_name}: {e}")
   LG.debug(f"Time for contourf {prop_name}: {time()-t0}")

   # Add inset label if needed
   if inset_label:
      txt = ax.text(1, 0, inset_label, va='bottom', ha='right', color='k',
                    fontsize=12,
                    bbox=dict(boxstyle="round", fc=(1, 1, 1, 0.9), ec=None),
                    transform=ax.transAxes
                    )
      txt.set_clip_on(True)
   LG.debug(f'Plotted {prop_name}')

   # return C


@log_help.timer(LG, LGp)
def scalar_plot_old(ax, crs_data, lons, lats, prop,
                delta, vmin, vmax, cmap,
                levels=None, inset_label='', prop_name=''):
   """
   Plot a scalar (2D) field using contourf on a geographic axis.

   Parameters
   ----------
   ax : matplotlib.axes._subplots.AxesSubplot
       The axes on which to plot.
   crs_data : cartopy.crs
       The CRS of the data (used in the `transform` argument).
   lons, lats : 2D ndarray
       Longitude and latitude meshgrids matching the data grid.
   prop : 2D ndarray
       The scalar field to be plotted.
   delta : float
       Step size between color levels if `levels` is computed automatically.
   vmin, vmax : float
       Minimum and maximum values for colormap normalization.
   cmap : str or colormap
       Name of the colormap (defined in `mycolormaps` or default matplotlib).
   levels : list[float] or None, optional
       Discrete contour levels. If None, they're computed from vmin to vmax.
       If an empty list, defaults to automatic linear spacing.
   inset_label : str, optional
       A label shown in the bottom-right corner of the plot (e.g. timestamp).
   prop_name : str, optional
       Name of the property being plotted (used in logs).

   Returns
   -------
   contourf : QuadContourSet or None
       The contourf handle for the colorbar, or None if plotting failed.
   """
   LG.debug(f'Plotting {prop_name}')

   try:
       msg = f'{prop_name} lims: {vmin}/{np.nanmin(prop):.1f}/{np.nanmax(prop):.1f}/{vmax}'
   except Exception as e:
       msg = f'Failed to compute min/max for {prop_name}: {e}'
   LG.debug(msg)

   if len(levels) > 0:
      norm = BoundaryNorm(levels,len(levels))
   else:
      levels = np.arange(vmin,vmax,delta)
      norm = None

   if isinstance(cmap, str):
      cmap = mycolormaps.get(cmap, cmap)  # fallback to matplotlib default

   # Plot the data
   try:
      LG.debug(f"Contouring with {len(levels)} Levels")
      t0 = time()
      ax.contourf(lons, lats, prop,
                  levels=levels, extend='max', norm=norm,
                  vmin=vmin, vmax=vmax, cmap=cmap,
                  transform=crs_data,
                  antialiased=False
                  )
      LG.debug(f"Time for contourf {prop_name}: {time()-t0}")
      LG.debug(f"Contoured")
   except Exception as e:
      LG.warning(f"Failed to plot {prop_name}: {e}")
      # C = None

   # Add inset label if needed
   if inset_label:
      txt = ax.text(1, 0, inset_label, va='bottom', ha='right', color='k',
                    fontsize=12,
                    bbox=dict(boxstyle="round", fc=(1, 1, 1, 0.9), ec=None),
                    transform=ax.transAxes
                    )
      txt.set_clip_on(True)
   LG.debug(f'Plotted {prop_name}')

   # return C


@log_help.timer(LG, LGp)
def plot_colorbar(cmap,delta=4,vmin=0,vmax=60,levels=None,name='cbar',
                                        units='',fs=18,norm=None,extend='max'):
   """
   Generate colorbar for the colormap cmap.
   vmin,vmax,delta: min, max, and step for colormap
   cmap: string of colormap it has to be defined in the local dictionary mycolormaps or be an acceptable matplotlib.colormap name
   Several options for the levels and color range:
   levels = None: levels remain none and are, hence, ignored
   levels = []  : a list of levels is computed from vmin to vmax with delta steps
   levels = [#] : the list provided is respected
   """
   if isinstance(cmap, str):
       if cmap in mycolormaps and mycolormaps[cmap] is not None:
           cmap = mycolormaps[cmap]
       else:
           try:
               cmap = plt.get_cmap(cmap)
           except Exception:
               cmap = plt.get_cmap("viridis")
   elif cmap is None:
       cmap = plt.get_cmap(None)
   
   fig, ax = plt.subplots()
   fig.set_figwidth(11)
   img = np.random.uniform(vmin,vmax,size=(40,40))
   
   if levels is None:
       levels = []
   # if type(levels) != type(None) and len(levels) == 0:
   #    levels=np.arange(vmin,vmax,delta)

   ## if len(levels) > 0:
   ##    norm = BoundaryNorm(levels,len(levels))
   ## else:
   ##    LG.critical(f'DELTA: {delta} {type(delta)}')
   ##    if np.isnan(delta): levels = None
   ##    else: levels = np.arange(vmin,vmax,delta)
   ##    norm = None
   # if levels is None:
   #    norm = None
   # else:
   #    if len(levels) > 0:
   #       norm = BoundaryNorm(levels,len(levels))
   #    else:
   #       levels = np.arange(vmin,vmax,delta)
   #       norm = None

   if np.isnan(delta):   # smooth gradient
      try:
         img = ax.contourf(img, cmap=cmap,
                                vmin=vmin, vmax=vmax,
                                # shading=shade, transform=crs_data,
                                antialiased=True)
      except Exception as e:
         LG.warning(f"Failed colorbar {e}")
   else:
      if len(levels) == 0: levels = np.arange(vmin, vmax + delta * 0.001, delta)
      else: pass
      norm = BoundaryNorm(levels, cmap.N)
      try:
         img = ax.contourf(img, cmap=cmap, norm=norm,
                        # vmin=vmin, vmax=vmax,  # Optional if using norm
                                # shading=shade, transform=crs_data,
                                antialiased=True)
      except Exception as e:
         LG.warning(f"Failed colorbar {e}")


   # img = ax.contourf(img, levels=levels,
   #                        extend=extend,
   #                        antialiased=True,
   #                        cmap=cmap,
   #                        norm=norm,
   #                        vmin=vmin, vmax=vmax)
   plt.gca().set_visible(False)
   divider = make_axes_locatable(ax)
   cax = divider.new_vertical(size="5%", pad=0.25, pack_start=True)
           #2.95%"
   fig.add_axes(cax)
   cbar = fig.colorbar(img, cax=cax, orientation="horizontal")
   cbar.ax.set_xlabel(units, fontsize=fs)
   # fig.savefig(f'{name}.png', transparent=True,
   #                            bbox_inches='tight', pad_inches=0.1)
   # plt.close('all')  #XXX are you sure???
   return ax


@log_help.timer(LG, LGp)
def vector_plot(ax, crs_data, lons,lats,UV, dens=1.5,color='k'):
   """
   Plot a vector property. 
   fig: matplotlib figure to plot in. XXX unnecessary??
   ax: axis to plot in
   orto: geographical projection (transform argument)
   lons,lats: (nx,ny) matrix of grid longitudes and latitudes
   U,V: (nx,ny) U and V components of the vector field
   dens: density of arrows in the map
   color: color of the arrows
   """
   t0 = time()
   if np.isnan(UV).all():
       LG.warning("Skipping vector_plot: UV data is all NaN")
       return
   LG.debug(f"Density in streamplot: {dens:.3f}")
   ax.streamplot(lons,lats, UV[0,:,:], UV[1,:,:],
                            color=color, linewidth=1, density=dens,
                            arrowstyle='->',arrowsize=2.5,
                            transform=crs_data)
   LG.debug(f"Time for streamplot: {time()-t0}")


@log_help.timer(LG, LGp)
def barbs_plot(ax, crs_data, lons,lats,UV, n=1,color=(0,0,0,0.75)):
   """
   Plot a wind barbs
   fig: matplotlib figure to plot in. XXX unnecessary??
   ax: axis to plot in
   orto: geographical projection (transform argument)
   lons,lats: (nx,ny) matrix of grid longitudes and latitudes
   U,V: (nx,ny) U and V components of the vector field
   """
   U = UV[0,:,:]
   V = UV[1,:,:]
   if np.isnan(U).all() or np.isnan(V).all():
       LG.warning("Skipping barbs_plot: UV data is all NaN")
       return
   n = 1
   f = 2
   ax.barbs(lons[::n,::n].values, lats[::n,::n].values, U[::n,::n],V[::n,::n],
            color=color, length=4, pivot='middle',
            sizes=dict(emptybarb=0.25/f, spacing=0.2/f, height=0.5/f),
            linewidth=0.75, transform=crs_data)

