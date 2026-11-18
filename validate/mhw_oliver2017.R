## Marine heatwaves: reference check against Oliver et al. (2017), "The
## unprecedented 2015/16 Tasman Sea marine heatwave", Nat Commun 8:16101,
## and Kajtar et al. (2021), JSHESS 71(3):284-302.
##
## Oliver's recipe (Methods): NOAA OI SST V2 (AVHRR-only, daily, 0.25 deg;
## obtained for 1982-01-01..2016-07-05), spatially averaged over the SEAus
## box 147-155E, 45-37S; Hobday et al. (2016) events on a 1982-2005
## climatology (11-day window, 31-day smoothing, 90th percentile, >= 5 days,
## gaps <= 2 days joined). Published: 2015-09-09..2016-05-16, 251 days,
## mean intensity 1.8 C, max 2.9 C, cumulative 443 C-days.
## Kajtar's Tasman Sea box: 147-157E 37-46S, 1983-2012 climatology.
## Published: 2015-09-09..2016-07-22, 318 days, max 2.8 C.
##
## Data: OISST v2.1 per pixel (NCEI replaced V2 in 2020) for 1982-2025 over
## 147-157E, 46-37S, the union of the boxes. V2 is still served by NCEI:
## it is bit-identical to v2.1 before 2016 (checked here on sampled dates)
## and differs from 2016-01-01, so "V2" below is v2.1 to 2015 plus V2's own
## 2016-01-01..2016-07-05, Oliver's record end.
##
## Compared: boxes SEAus (Oliver), tasman45 (147-157E 37-45S, trend.sst's
## tasman box until 2026-11-18) and kajtar (trend.sst's tasman box since);
## baselines 1982-2005, 1982-2011 (ours), 1983-2012; tiers "pixels"
## (cos-latitude weighted mean of the 0.25 deg ocean pixels with centres in
## the box) and "S2 cells" (level-5 cells with centres in the box, from
## sums/oisst, as validate/mhw_event.R and the site do).
##
## Result (2026-11-17), the event containing 2016-01-01:
##   Kajtar reproduces exactly: kajtar pixels, v2.1, 1983-2012:
##     2015-09-09..2016-07-22, 318 d, max 2.80 C.
##   Oliver does not, quite: SEAus pixels, 1982-2005, same start date and
##     peak day (2015-12-19) in every run, but 245 d to 2016-05-10 (V2) or
##     249 d to 2016-05-14 (v2.1), mean 1.88-1.92 C, max 3.14 C, cumulative
##     460-479 C-days. The peak and the 1982-2005 climatology are all in
##     the pre-2016 data, identical in V2 and v2.1, so max 3.14 vs 2.9 comes
##     from something we cannot see: a step the paper does not state, or a
##     V2 revision since 2016. (Climatologies to 2015-12-31 or 2016-07-05,
##     not run here, give max 2.93-2.94 C but 245-249 d.)
##   The box's southern edge decides the duration: pixel boxes to 45S give
##     249-253 d ending mid-May, to 46S 318 d ending 2016-07-22. The S2
##     cells with centres in any of the three boxes reach 46.0S or beyond,
##     so the S2 tier gives 318-319 d for all of them: the site's OISST
##     matched Kajtar's event because of the cell footprint, not the box.
##     So trend.sst's tasman box now ends at 46S, Kajtar's, where the pixel
##     and S2 tiers agree (318 and 318-319 d).
##
## Rscript validate/mhw_oliver2017.R   (from the package root; the S2 tier
## needs sums/oisst). Windows are cached in cache/mhw/oliver2017/; the first
## run reads ~16,000 v2.1 files (local raad mirror if present, else NCEI)
## and ~210 V2 files from NCEI.

suppressMessages(devtools::load_all(quiet = TRUE))
library(heatwaveR)

root <- file.path("cache", "mhw", "oliver2017")
dir.create(root, recursive = TRUE, showWarnings = FALSE)

## the read window: 0.25 deg pixel edges; centres lon 147.125.., lat -37.125..
ext <- c(xmin = 147, xmax = 157, ymin = -46, ymax = -37)
lon <- seq(ext[["xmin"]] + 0.125, ext[["xmax"]] - 0.125, by = 0.25)
lat <- seq(ext[["ymax"]] - 0.125, ext[["ymin"]] + 0.125, by = -0.25)
px_lon <- rep(lon, times = length(lat))  ## pixel order: x fastest, north first
px_lat <- rep(lat, each = length(lon))

ncei <- "www.ncei.noaa.gov/data/sea-surface-temperature-optimum-interpolation"
local <- file.path("/rdsi/PUBLIC/raad/data", ncei)
v21_base <- if (dir.exists(local)) file.path(local, "v2.1/access/avhrr") else
  file.path("/vsicurl/https:/", ncei, "v2.1/access/avhrr")
v2_base <- file.path("/vsicurl/https:/", ncei, "v2/access/avhrr-only")
v21_dsn <- function(d) file.path(v21_base, format(d, "%Y%m"),
                                 sprintf("oisst-avhrr-v02r01.%s.nc", format(d, "%Y%m%d")))
v2_dsn <- function(d) file.path(v2_base, format(d, "%Y%m"),
                                sprintf("avhrr-only-v2.%s.nc", format(d, "%Y%m%d")))

read_window <- function(files, workers = 16L) {
  read_one <- function(f, ext) {
    dsn <- sprintf("vrt://NETCDF:\"%s\":sst?a_srs=EPSG:4326&unscale=true&ot=Float32", f)
    v <- vapour::gdal_raster_data(dsn, target_ext = unname(ext),
                                  target_res = c(0.25, 0.25), resample = "near")[[1]]
    as.integer(round(v * 100))  ## stored as 0.01 C integers: exact
  }
  mirai::daemons(workers)
  on.exit(mirai::daemons(0))
  v <- do.call(rbind, mirai::mirai_map(files, read_one, .args = list(ext = ext))[.stop])
  stopifnot(ncol(v) == length(px_lon))
  v
}

v21_file <- file.path(root, "oisst_window.rds")
if (!file.exists(v21_file)) {
  dates <- seq(as.Date("1982-01-01"), as.Date("2025-12-31"), by = "1 day")
  message(sprintf("reading %i OISST v2.1 days from %s", length(dates), v21_base))
  saveRDS(list(date = dates, sst100 = read_window(v21_dsn(dates))), v21_file)
}
v2_file <- file.path(root, "oisst_v2.rds")
if (!file.exists(v2_file)) {
  set.seed(2017)
  check <- sort(sample(seq(as.Date("1982-01-01"), as.Date("2015-12-31"), by = "1 day"), 24))
  dates <- c(check, seq(as.Date("2016-01-01"), as.Date("2016-07-05"), by = "1 day"))
  message(sprintf("reading %i OISST V2 days from NCEI", length(dates)))
  saveRDS(list(date = dates, check = check, sst100 = read_window(v2_dsn(dates), 8L)), v2_file)
}
v21 <- readRDS(v21_file)
v2 <- readRDS(v2_file)

## V2 = v2.1 before 2016: hold it to that on the sampled dates
ic <- match(v2$check, v2$date)
same <- identical(v2$sst100[ic, ], v21$sst100[match(v2$check, v21$date), ])
message(sprintf("V2 vs v2.1 on %i sampled pre-2016 dates: %s", length(ic),
                if (same) "identical" else "DIFFERENT"))
stopifnot(same)
i16 <- v2$date >= as.Date("2016-01-01")
v2m <- v21$sst100
v2m[match(v2$date[i16], v21$date), ] <- v2$sst100[i16, ]
keep_v2 <- v21$date <= as.Date("2016-07-05")

boxes <- list(
  SEAus    = c(xmin = 147, xmax = 155, ymin = -45, ymax = -37),
  tasman45 = c(xmin = 147, xmax = 157, ymin = -45, ymax = -37),
  kajtar   = c(xmin = 147, xmax = 157, ymin = -46, ymax = -37))
baselines <- list(
  "1982-2005" = c("1982-01-01", "2005-12-31"),
  "1982-2011" = c("1982-01-01", "2011-12-31"),
  "1983-2012" = c("1983-01-01", "2012-12-31"))

pixel_series <- function(m, b) {
  sel <- px_lon > b[["xmin"]] & px_lon < b[["xmax"]] &
         px_lat > b[["ymin"]] & px_lat < b[["ymax"]]
  x <- m[, sel, drop = FALSE] * 0.01
  w <- cos(px_lat[sel] * pi / 180)
  ok <- !is.na(x)
  stopifnot(all(rowSums(ok) == rowSums(ok)[1]))  ## fixed land mask
  as.vector((ifelse(ok, x, 0) %*% w) / (ok %*% w))
}

reg <- arrow::read_parquet("s2_registry.parquet")
cell_series <- function(b) {
  cin <- reg$cell[reg$lon >= b[["xmin"]] & reg$lon < b[["xmax"]] &
                  reg$lat >= b[["ymin"]] & reg$lat < b[["ymax"]]]
  rect <- s2::s2_bounds_rect(s2::s2_union_agg(s2::s2_cell_polygon(s2::as_s2_cell(cin))))
  message(sprintf("S2 cells in %s: %i, footprint %.1f..%.1fE %.1f..%.1fS",
                  paste(b, collapse = " "), length(cin), rect$lng_lo, rect$lng_hi,
                  -rect$lat_hi, -rect$lat_lo))
  so <- series_stats("sums/oisst", cin)
  data.frame(t = as.Date(so$date), temp = so$mean)
}

series <- list(
  list(label = "SEAus pixels", product = "V2",
       ts = data.frame(t = v21$date[keep_v2], temp = pixel_series(v2m[keep_v2, ], boxes$SEAus))))
for (bn in names(boxes)) {
  series[[length(series) + 1]] <- list(label = paste(bn, "pixels"), product = "v2.1",
    ts = data.frame(t = v21$date, temp = pixel_series(v21$sst100, boxes[[bn]])))
  series[[length(series) + 1]] <- list(label = paste(bn, "S2 cells"), product = "v2.1",
    ts = cell_series(boxes[[bn]]))
}

core <- as.Date("2016-01-01")
one_run <- function(ts, bl) {
  ts <- ts[ts$t >= as.Date("1982-01-01") & ts$t <= as.Date("2025-12-31"), ]
  e <- detect_event(ts2clm(ts, climatologyPeriod = bl))$event
  h <- e[e$date_start <= core & e$date_end >= core, ]
  stopifnot(nrow(h) == 1L)
  data.frame(start = h$date_start, peak = h$date_peak, end = h$date_end,
             days = h$duration, imean = round(h$intensity_mean, 2),
             imax = round(h$intensity_max, 2), icum = round(h$intensity_cumulative))
}
res <- do.call(rbind, lapply(series, function(s) {
  do.call(rbind, lapply(names(baselines), function(bl) {
    cbind(series = s$label, product = s$product, baseline = bl, one_run(s$ts, baselines[[bl]]))
  }))
}))

cat("\nOliver et al. 2017 (V2, SEAus, 1982-2005): 2015-09-09..2016-05-16, 251 d, imean 1.8, imax 2.9, icum 443\n")
cat("Kajtar et al. 2021 (147-157E 37-46S, 1983-2012): 2015-09-09..2016-07-22, 318 d, imax 2.8\n\n")
print(res, row.names = FALSE)
write.csv(res, file.path(root, "events.csv"), row.names = FALSE)
