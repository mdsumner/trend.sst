## Marine heatwaves (Hobday et al. 2016, categories Hobday et al. 2018),
## vectorised over pixels, on spells (github.com/hypertidy/spells).
##
## Until 2026-11 this file had its own engine, a faithful reimplementation
## of heatwaveR 0.5.5 ts2clm() + detect_event() defaults. That engine
## moved into spells, which reproduces it as its "heatwaveR-0.5.5" parity
## mode: spells' tests check it against heatwaveR 0.5.5 and against this
## file's old engine (spells tests/testthat/test-trend-sst.R), so nothing
## published here changes. Moving to spells' clean rules is a separate,
## visible step, with its own labels.
##
## The rules, as heatwaveR 0.5.5 has them:
## - doy on a 366-day calendar: non-leap years skip slot 60 (Feb 29)
## - baseline spread to (doy, year); Feb 29 in non-leap years filled with
##   round(mean(doy 59, doy 61), 2); a missing baseline day filled with
##   its doy's mean across the years (the old engine stopped instead)
## - window: +-5 doy rows, wrapping within the year; pooled mean and
##   type-7 90th percentile
## - 31-day circular centred running mean of seas and thresh, then
##   round to 4 decimals
## - exceedance is x > thresh (NA counts as seas); runs >= 5 days; gaps of
##   1..2 days joined, except the leading gap, and a trailing gap <= 2
##   days at the series end is joined (heatwaveR 0.5.5's quirk)
## - categories: Hobday 2018 I-IV by floor((x - seas) / (thresh - seas)),
##   event days below 1x counted as I (trend.sst's rule, not heatwaveR's)

#' The definition every product here uses: Hobday 2016 detection with
#' Hobday 2018 categories, on heatwaveR 0.5.5's rules, with trend.sst's
#' category rule. `baseline` is the reference period, two dates.
mhw_def <- function(baseline) {
  spells::hobday2018(baseline, parity = "heatwaveR-0.5.5",
                     category = spells::categories(gap_days = "I"))
}

#' Day of year on a 366-day calendar.
mhw_doy <- function(dates) spells::slot_366(dates)

#' Climatology for every column of x (time x pixel, daily).
#' Returns list(seas, thresh), each 366 x ncol(x), and the spells
#' baseline they come from.
mhw_clim <- function(x, dates, baseline) {
  b <- spells::spell_baseline(x, dates, mhw_def(baseline))
  list(seas = b$seas, thresh = b$thresh, baseline = b)
}

#' Per-column events for a time x pixel chunk. Returns the event mask and
#' daily category (0 = no event; 1..4 = Hobday 2018 I-IV by
#' (x - seas) / (thresh - seas), event days below 1x counted as I), and
#' the anomaly x - seas.
mhw_detect <- function(x, dates, clim) {
  m <- spells::spell_mask(x, dates, clim$baseline)
  list(event = m$event, category = m$category, anom = m$anom)
}

#' MHW pilot regions on the native MUR grid. A region is a pixel window
#' (origin -179.995, 89.995, 0.01 deg: pixel centres on whole hundredths)
#' plus the event windows its figures and per-pixel stats focus on.
#' lon0/lat0 are the NW pixel centre; nx/ny must be multiples of 50 (the
#' Zarr chunk). Each window: stats = dates for per-pixel stats, plot =
#' dates for the time-series panel.
mhw_regions <- list(
  tasman = list(
    title = "Tasman Sea", lon0 = 147, lat0 = -37, nx = 1000L, ny = 900L,
    windows = list(
      ev1516 = list(label = "2015/16", stats = c("2015-08-01", "2016-06-30"),
                    plot = c("2015-08-01", "2016-07-31"), map_label = "Aug 2015–Jun 2016"),
      ev2026 = list(label = "2026", stats = c("2026-01-01", "2026-12-31"),
                    plot = c("2026-01-01", "2026-12-31"), map_label = NULL))),
  nw = list(
    title = "North-west Australia", lon0 = 113, lat0 = -11, nx = 1500L, ny = 1100L,
    windows = list(
      ev2425 = list(label = "2024/25", stats = c("2024-08-01", "2025-05-31"),
                    plot = c("2024-07-01", "2025-06-30"), map_label = "Aug 2024–May 2025"),
      ev2026 = list(label = "2026", stats = c("2026-01-01", "2026-12-31"),
                    plot = c("2026-01-01", "2026-12-31"), map_label = NULL))),
  wa = list(
    title = "Western Australia", lon0 = 110, lat0 = -21, nx = 600L, ny = 1200L,
    windows = list(
      ev1011 = list(label = "2010/11", stats = c("2010-12-01", "2011-05-31"),
                    plot = c("2010-11-01", "2011-06-30"), map_label = "Dec 2010–May 2011"),
      ev2026 = list(label = "2026", stats = c("2026-01-01", "2026-12-31"),
                    plot = c("2026-01-01", "2026-12-31"), map_label = NULL))))

mhw_region <- function(name) {
  r <- mhw_regions[[name]]
  if (is.null(r)) stop("unknown region '", name, "'; have: ",
                       paste(names(mhw_regions), collapse = ", "))
  stopifnot(r$nx %% 50L == 0L, r$ny %% 50L == 0L)
  r$name <- name
  r$xoff <- as.integer(round((r$lon0 + 179.99) * 100))
  r$yoff <- as.integer(round((89.99 - r$lat0) * 100))
  r$lon <- round(r$lon0 + 0.01 * (seq_len(r$nx) - 1L), 2)
  r$lat <- round(r$lat0 - 0.01 * (seq_len(r$ny) - 1L), 2)
  r$bbox <- c(xmin = r$lon0 - 0.005, xmax = max(r$lon) + 0.005,
              ymin = min(r$lat) - 0.005, ymax = r$lat0 + 0.005)
  r$root <- file.path("cache", "mhw", name)
  r
}
