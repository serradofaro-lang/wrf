#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import log_help
import logging
LG = logging.getLogger(f"main.{__name__}")

import requests
import pandas as pd
import datetime as dt
import stations.utils as ut

UTCshift = dt.datetime.now() - dt.datetime.utcnow()
UTCshift = dt.timedelta(hours = round(UTCshift.total_seconds()/3600))

def download_data(lat=None, lon=None, **kwargs):
   """
   Download current weather data from OpenWeatherMap API using auto-constructed URL
   
   Args:
       lat (float): Latitude
       lon (float): Longitude
   """
   # Hardcoded AppID as requested
   appid = "46b20b0407a41f2b8d6095ee5636b275"
   
   if lat is None or lon is None:
       LG.error("Latitude or Longitude not provided for OpenWeatherMap.")
       return pd.DataFrame()

   # Construct the clean URL
   base_url = "https://api.openweathermap.org/data/2.5/weather"
   clean_url = f"{base_url}?lat={lat}&lon={lon}&units=metric&lang=sp,es&appid={appid}"
   
   LG.info(f'Requesting OWM: {clean_url}')
   try:
      response = requests.get(clean_url)
      response.raise_for_status()
      data = response.json()
   except Exception as e:
      LG.error(f"Failed to fetch OWM data: {e}")
      return pd.DataFrame()

   # Parse the single observation
   # OWM 'dt' is unix timestamp (UTC)
   timestamp = dt.datetime.utcfromtimestamp(data['dt']).replace(minute=0, second=0, microsecond=0) 
   # Adjust to local time if that's what the system expects, or keep UTC.
   # schema.py says "datetime (UTC)", but other scripts seem to adjust.
   # Let's keep it consistent with what seems to be the convention: UTC object.
   
   main = data.get('main', {})
   wind = data.get('wind', {})
   
   # Convert units if needed (API call has &units=metric so these are Metric)
   # Temp: Celsius
   # Wind: meter/sec (Metric default) -> convert to km/h per schema expectation?
   # NOTE: standard unit for wind in OWM metric is m/s. 
   # schema.py says km/h. 
   
   wspd_ms = float(wind.get('speed', 0))
   wspd_kmh = wspd_ms * 3.6
   
   gust_ms = float(wind.get('gust', 0))
   gust_kmh = gust_ms * 3.6 if gust_ms else float('nan')
   
   sys = data.get('sys', {})
   sunrise_ts = sys.get('sunrise')
   sunset_ts  = sys.get('sunset')
   
   sunrise_dt = dt.datetime.utcfromtimestamp(sunrise_ts) if sunrise_ts else pd.NaT
   sunset_dt  = dt.datetime.utcfromtimestamp(sunset_ts) if sunset_ts else pd.NaT

   # Construct row
   row = {
       "time": timestamp,
       "wind_speed_avg": wspd_kmh,
       "wind_speed_max": gust_kmh,
       # 'wind_speed_min' is not provided by OWM current weather
       "wind_speed_min": float('nan'), 
       "wind_heading": float(wind.get('deg', 0)),
       "temperature": float(main.get('temp', 0)),
       "rh": float(main.get('humidity', 0)),
       "pressure": float(main.get('pressure', 0)), # hPa
       "swdown": float('nan'), # Not standard in current weather response
       "sunrise": sunrise_dt,
       "sunset": sunset_dt
   }
   
   df = pd.DataFrame([row])
   df = ut.reconcile_station_dataframe(df)
   
   return df
