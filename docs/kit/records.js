// trend kit: the family registry. One entry per record: where its site
// and sums live, its units, how its metrics are coloured, how its code
// generator describes the store. Sites pick their record by key in
// site.js; an explorer can also load another record's source by
// "record:source" (cross-origin from that record's site; GitHub Pages
// serves Access-Control-Allow-Origin: *), with that record's units and
// bucket, so combinations need no copied data.
//
// Metric spec: label, type "div" (symmetric about 0, +-lim) or "seq"
// (min..max of the cells), digits for display.
window.TREND_RECORDS = {
  sst: {
    title: "trend.sst", label: "Sea surface temperature",
    site: "https://mdsumner.github.io/trend.sst/",
    bucket: "aad-derived/trend-sst",
    unit: "C", digits: 2, value: "mean_sst",
    tip: c => `mean ${c.mean} C &middot; trend ${c.trend ?? "-"} C/dec`,
    metrics: {
      trend: { label: "Trend (C/decade)", lim: 0.6, type: "div", digits: 2 },
      anom:  { label: "Last 12 months vs baseline (C)", lim: 1.5, type: "div", digits: 2 },
      mean:  { label: "Mean SST (C)", type: "seq", digits: 1 }
    },
    sources: {
      ghrsst: { label: "GHRSST", long: "GHRSST MUR", col: "--series-2" },
      oisst:  { label: "OISST", long: "OISST v2.1", col: "--series-1" }
    },
    combos: {
      diff: { label: "GHRSST - OISST", a: "ghrsst", b: "oisst", vars: ["g", "o"],
        metrics: {
          trend: { label: "Trend difference (C/decade)", lim: 0.2, type: "div", digits: 3 },
          anom:  { label: "12-month anomaly difference (C)", lim: 0.5, type: "div", digits: 2 },
          mean:  { label: "Mean difference (C)", lim: 1, type: "div", digits: 2 }
        } }
    },
    code: {
      hdr: "newest ~10 days are provisional",
      store: ["object storage. The full record is ~9,000 files per source, so"],
      source: ["The source MUR COGs are public too (pixel-level work):",
               "  s3://us-west-2.opendata.source.coop/ausantarctic/ghrsst-mur-v2/"]
    },
    status: { fresh: [3, 10], ghost: "oisst", region: "cr",
      note: "Area-weighted mean SST (C) straight from the sums." }
  },

  sla: {
    title: "trend.sla", label: "Sea level anomaly",
    site: "https://mdsumner.github.io/trend.sla/",
    bucket: "aad-derived/trend-sla",
    unit: "mm", digits: 1, value: "mean_sla",
    tip: c => `mean ${c.mean} mm &middot; trend ${c.trend ?? "-"} mm/yr`,
    metrics: {
      trend: { label: "Trend (mm/yr)", lim: 8, type: "div", digits: 1 },
      anom:  { label: "Last 12 months vs 1993-2012 (mm)", lim: 150, type: "div", digits: 0 },
      mean:  { label: "Mean SLA (mm)", type: "seq", digits: 0 }
    },
    sources: {
      "sla-cmems": { label: "SLA", long: "CMEMS DUACS SLA", col: "--series-1" }
    },
    code: {
      hdr: "near-real-time days are replaced as delayed-time arrives",
      store: ["object storage. Values are in METRES (the site shows mm). The full",
              "record is ~12,000 files, so"],
      source: ["The source grids are public Copernicus ARCO Zarr (pixel-level",
               "work); find them with the cmemsarco R package."]
    },
    status: { fresh: [3, 10], region: "cr",
      note: "Area-weighted mean sea level anomaly (mm, relative to the product's 1993-2012 reference) straight from the sums." }
  },

  chl: {
    title: "trend.chl", label: "Chlorophyll-a",
    site: "https://mdsumner.github.io/trend.chl/",
    bucket: "aad-derived/trend-chl",
    unit: "", digits: 3, value: "mean_log10chl",
    tip: c => `mean ${c.mean} log10 &middot; trend ${c.trend ?? "-"} log10/decade`,
    metrics: {
      trend: { label: "Trend (log10 per decade)", lim: 0.1, type: "div", digits: 3 },
      anom:  { label: "Last 12 months vs 1998-2017 (log10)", lim: 0.3, type: "div", digits: 2 },
      mean:  { label: "Mean log10 chl-a (mg m-3)", type: "seq", digits: 2 }
    },
    sources: {
      "occci-log10chl": { label: "Chl-a (OC-CCI v6.0)", long: "ESA OC-CCI v6.0 chl-a", col: "--series-1" }
    },
    code: {
      hdr: "sums are of log10(chl-a), one file per 5-day composite",
      store: ["object storage. Values are log10(chl-a, mg m-3); means are",
              "geometric. The full record is ~2,100 files, so"],
      source: ["The source grids are ESA OC-CCI v6.0 COGs on Pawsey Acacia",
               "(aad-derived/esacci-oc/v6.0-release/geographic/5day/chlor_a)."]
    },
    status: { fixed: "Fixed release v6.0", meta: "5-day composites", region: "cr",
      note: "Area-weighted mean log10 chlorophyll-a (mg m-3) over ocean cells, straight from the sums: a geometric mean, so -1 is 0.1 mg m-3 and 0 is 1 mg m-3." }
  },

  ice: {
    title: "trend.ice", label: "Sea ice",
    site: "https://mdsumner.github.io/trend.ice/",
    bucket: "aad-derived/trend-ice/s2",
    unit: "%", digits: 1, value: "mean_sic",
    tip: c => `mean ${c.mean} % &middot; trend ${c.trend ?? "-"} %/dec`,
    metrics: {
      trend: { label: "Trend (% per decade)", lim: 4, type: "div", digits: 2 },
      anom:  { label: "Last 12 months vs baseline (%)", lim: 15, type: "div", digits: 1 },
      mean:  { label: "Mean concentration (%)", type: "seq", digits: 1 }
    },
    // the region series can also be shown as a total: with w the cell's
    // mean daily ocean area (km2), sum(w * mean) is sea ice area
    total: { label: "Area", unit: "million km2", digits: 2, scale: 1e-8 },
    sources: {
      // the CDR is one bipolar source from two stores (sums/<store>/),
      // one per hemisphere, whose cells are disjoint
      "cdr-sic": { label: "CDR", long: "NSIDC CDR (25 km, 1978-, both poles)", col: "--series-1",
                   stores: { "cdr-sic": "s", "cdr-sic-north": "n" } },
      "asi-sic": { label: "ASI", long: "Bremen ASI AMSR2 (3.125 km, 2012-, south)", col: "--series-2" }
    },
    code: {
      hdr: "sums are sea ice concentration as a fraction, weights are pixel areas (km2)",
      store: ["object storage. Values are concentration as a FRACTION (the site",
              "shows percent); SUM(sumwx) is sea ice area in km2. The full",
              "record is ~17,500 files per CDR hemisphere, so"],
      source: ["The source files are read through published indexes:",
               "  https://data.source.coop/ausantarctic/ausantarctic-scratch/seaice/"]
    },
    status: { fresh: [30, 60], ghost: "cdr-sic", region: "global", unit: "M km2", digits: 2,
      meta: "daily fields, refreshed weekly",
      note: "Sea ice area (million km2): concentration times pixel area, summed straight from the sums." }
  }
};
