#!/usr/bin/python3
# -*- coding: UTF-8 -*-

STATION_CSV_COLUMNS = [
    "time",         # datetime (UTC)
    # "station_id",   # str
    # "lat",          # float (location of WRF grid point)
    # "lon",          # float
    "wind_speed_min", # float (km/h)
    "wind_speed_avg", # float (km/h)
    "wind_speed_max", # float (km/h)
    "wind_heading",   # float (degrees)
    "temperature",    # float (°C)
    "rh",             # float (%)
    "pressure",       # float (hPa)
    "swdown",       # float (hPa)
    "sunrise",      # datetime (UTC)
    "sunset",       # datetime (UTC)
]

