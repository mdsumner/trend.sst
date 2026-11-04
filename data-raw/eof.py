#!/usr/bin/env python3
"""data-raw/eof.py -- empirical orthogonal functions (EOFs) of monthly means.

  python3 data-raw/eof.py [data_dir] [source] [unit] [n_modes] [like]

  defaults: docs/data, sla-cmems, mm, 6, (none)

like: another source in data_dir; only cells it also has are used (e.g.
GHRSST MUR covers lakes worldwide, so trend.sst runs it like oisst).

Reads the site's own exports in data_dir:
  cells-<source>.json    cell order, lon/lat, month labels
  monthly-<source>.bin   Float32 cell x month means, cell-major
  status.json            last date, to drop a partial final month
and writes data_dir/eof-<source>.json for docs/modes.html. The same
script serves trend.sla (sla-cmems, mm) and trend.sst (oisst, ghrsst,
degC); keep the two copies identical.

The monthly means are exact projections of the grist sums (ratio of
summed sumwx to summed sumw per cell and month), so this is EOF analysis
of the published record with nothing re-read from the source.

Method, all per cell:
  1. drop the partial final month (status.json last date not a month end)
  2. mask inland water that is in the product grid but is not ocean
     (see MASKS below), and keep only cells the `like` source has

  3. remove mean, linear trend and the mean seasonal cycle (12 monthly
     offsets), fitted jointly by least squares
  4. SVD of the month x cell anomaly matrix, cells equally weighted (S2
     level-5 cells are roughly equal area)
Each mode is reported as a pattern in the source's unit per standard
deviation of its principal component (PC), and the PC in standard units,
so pattern * PC is the mode's contribution in that unit. Sign convention: mode 1 is positive
where the Nino 3.4 box loads; other modes are positive at their largest
loading.
"""
import json
import os
import sys

import numpy as np

## cells to exclude: (label, lat_min, lat_max, lon360_min, lon360_max).
## Inland water is in some product grids but is not ocean. The Caspian
## is in the CMEMS grid; its level history (a ~1.5 m fall
## 1995-2021, then a ~1.2 m rise from 2022-09) dominated the first
## unmasked analysis as a mode of its own (12% of variance).
## OISST also carries the Great Lakes (its second mode, unmasked) and
## Ladoga/Onega. Boxes test cell centres (Great Lakes starts at 40.8N so
## the coastal ocean cell centred at 40.65N, 77.9W stays in).
MASKS = [("Caspian Sea", 36.0, 48.0, 46.0, 56.0),
         ("Great Lakes", 40.8, 49.5, 267.5, 285.5),
         ("Ladoga, Onega, Ilmen", 58.5, 63.0, 29.0, 37.0)]
NINO34 = (-5.0, 5.0, 190.0, 240.0)


def month_end(iso):
    y, m, d = (int(x) for x in iso.split("-"))
    nxt = (y + (m == 12), m % 12 + 1)
    import datetime as dt
    return (dt.date(*nxt, 1) - dt.timedelta(days=1)).day == d


def main():
    a = sys.argv[1:]
    data = a[0] if len(a) > 0 else "docs/data"
    SRC = a[1] if len(a) > 1 else "sla-cmems"
    unit = a[2] if len(a) > 2 else "mm"
    k = int(a[3]) if len(a) > 3 else 6
    like = a[4] if len(a) > 4 else None
    meta = json.load(open(os.path.join(data, "cells-%s.json" % SRC)))
    status = json.load(open(os.path.join(data, "status.json")))
    cells = meta["cells"]
    months = list(meta["months"])
    m = np.fromfile(os.path.join(data, "monthly-%s.bin" % SRC), "<f4")
    m = m.reshape(len(cells), len(months)).astype(float)

    last = status["sources"][SRC]["last"]
    if months[-1] == last[:7] and not month_end(last):
        months = months[:-1]
        m = m[:, :len(months)]

    lat = np.array([c["lat"] for c in cells])
    lon = (np.array([c["lon"] for c in cells]) + 360.0) % 360.0
    keep = np.isfinite(m).all(axis=1)
    masked = []
    for label, a0, a1, o0, o1 in MASKS:
        s = (lat > a0) & (lat < a1) & (lon > o0) & (lon < o1)
        masked.append({"label": label, "cells": int(s.sum())})
        keep &= ~s
    if like:
        other = json.load(open(os.path.join(data, "cells-%s.json" % like)))
        ids = set(c["id"] for c in other["cells"])
        s = np.array([c["id"] not in ids for c in cells])
        masked.append({"label": "not in %s" % like, "cells": int((s & keep).sum())})
        keep &= ~s
    X = m[keep].T                                 # month x cell

    nt = len(months)
    t = np.arange(nt) / nt
    moy = np.array([int(s[5:]) - 1 for s in months])
    A = np.column_stack([np.ones(nt), t] +
                        [(moy == j).astype(float) for j in range(1, 12)])
    beta = np.linalg.lstsq(A, X, rcond=None)[0]
    R = X - A @ beta

    U, S, Vt = np.linalg.svd(R, full_matrices=False)
    var = S ** 2 / np.sum(S ** 2)
    la, lo = lat[keep], lon[keep]
    a0, a1, o0, o1 = NINO34
    box = (la >= a0) & (la <= a1) & (lo >= o0) & (lo <= o1)
    n34 = R[:, box].mean(axis=1)

    modes = []
    for j in range(k):
        pc = U[:, j] * S[j]
        sd = pc.std()
        pat = Vt[j] * sd                          # unit per PC standard deviation
        sign = np.sign(pat[box].mean()) if j == 0 else np.sign(pat[np.argmax(np.abs(pat))])
        sign = sign or 1.0
        pc, pat = pc * sign / sd, pat * sign
        full = [None] * len(cells)
        for i, v in zip(np.flatnonzero(keep), pat):
            full[i] = round(float(v), 2)
        q = np.sort(pat ** 2)[::-1]
        top = float(q[:max(1, len(q) // 20)].sum() / q.sum())
        modes.append({
            "mode": j + 1,
            "top5_share": round(top, 3),
            "variance": round(float(var[j]), 4),
            "r_nino34_box": round(float(np.corrcoef(pc, n34)[0, 1]), 3),
            "pc_raw_sd": round(float(sd), 4),
            "pc": [round(float(v), 3) for v in pc],
            "pattern": full,
        })
        print("mode %i: %.1f%% of variance, r with Nino 3.4 box anomaly %.2f, "
              "top 5%% of cells hold %.0f%%%s"
              % (j + 1, 100 * var[j], modes[-1]["r_nino34_box"], 100 * top,
                 "  <- CONCENTRATED: check for non-ocean cells" if top > 0.7 else ""))

    out = {
        "source": SRC,
        "unit": unit,
        "months": months,
        "cells_used": int(keep.sum()),
        "masked": masked,
        "method": ("per-cell mean, linear trend and mean seasonal cycle removed; "
                   "SVD of month x cell anomalies, cells equally weighted"),
        "variance_first10": [round(float(v), 4) for v in var[:10]],
        "modes": modes,
    }
    path = os.path.join(data, "eof-%s.json" % SRC)
    with open(path, "w") as f:
        json.dump(out, f, separators=(",", ":"))
    print("wrote %s: %i modes, %i months x %i cells"
          % (path, k, nt, int(keep.sum())))


if __name__ == "__main__":
    main()
