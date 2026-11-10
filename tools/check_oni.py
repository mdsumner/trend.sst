#!/usr/bin/env python3
"""tools/check_oni.py -- check EOF mode 1 against NOAA's Oceanic Nino Index.

  python3 tools/check_oni.py [docs/data/eof-oisst.json] [mode]

The ONI is a 3-month running mean of ERSST v5 SST anomalies in the
Nino 3.4 box: independent of this record's data. It is downloaded from
NOAA CPC (needs outbound https; Setonix login nodes have it). The mode's
time series is smoothed the same way (3-month centred mean) and matched
on the centre month of each ONI season (DJF -> January, ..., NDJ ->
December). Prints the correlation at lags -6..+6 months (positive lag:
the mode leads the ONI).
"""
import json
import sys
import urllib.request

import numpy as np

URL = "https://www.cpc.ncep.noaa.gov/data/indices/oni.ascii.txt"
SEAS = ["DJF", "JFM", "FMA", "MAM", "AMJ", "MJJ",
        "JJA", "JAS", "ASO", "SON", "OND", "NDJ"]

path = sys.argv[1] if len(sys.argv) > 1 else "docs/data/eof-oisst.json"
mode = int(sys.argv[2]) if len(sys.argv) > 2 else 1
e = json.load(open(path))
pc = np.array(e["modes"][mode - 1]["pc"])
months = e["months"]

oni = {}
with urllib.request.urlopen(URL, timeout=60) as r:
    for line in r.read().decode().splitlines():
        f = line.split()
        if len(f) == 4 and f[0] in SEAS:
            oni["%s-%02i" % (f[1], SEAS.index(f[0]) + 1)] = float(f[3])

sm = np.convolve(pc, np.ones(3) / 3, mode="same")
sm[0] = sm[-1] = np.nan
idx = {m: i for i, m in enumerate(months)}
print("%s mode %i vs ONI (%s)" % (e["source"], mode, URL))
for lag in range(-6, 7):
    a, b = [], []
    for m, v in oni.items():
        i = idx.get(m)
        if i is None or not 0 <= i - lag < len(sm):
            continue
        x = sm[i - lag]
        if np.isfinite(x):
            a.append(x)
            b.append(v)
    r = np.corrcoef(a, b)[0, 1] if len(a) > 24 else float("nan")
    print("  lag %+3i months: r = %.3f  (n = %i)" % (lag, r, len(a)))
