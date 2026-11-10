## Marine heatwaves (Hobday et al. 2016), vectorised over pixels.
## A faithful reimplementation of heatwaveR 0.5.5 ts2clm() + detect_event()
## defaults for complete daily series, so a whole chunk of pixel series
## (time x pixel matrix) shares one set of day-of-year window indices.
## Parity with heatwaveR is checked in validate/mhw_tasman_pixels.R.
##
## Conventions copied from heatwaveR:
## - doy on a 366-day calendar: non-leap years skip slot 60 (Feb 29)
## - baseline spread to (doy, year); Feb 29 in non-leap years filled with
##   round(mean(doy 59, doy 61), 2)
## - window: +-5 doy rows, wrapping the year; pooled mean and type-7
##   90th percentile
## - 31-day circular centred running mean of seas and thresh, then
##   round to 4 decimals
## - exceedance is x > thresh; runs >= 5 days; FALSE gaps of 1..2 days
##   joined, except the leading gap (heatwaveR also joins a trailing gap
##   <= 2 days at series end; we copy that quirk for parity)

mhw_doy <- function(dates) {
  y <- as.integer(format(dates, "%Y"))
  d <- as.integer(format(dates, "%j"))
  leap <- (y %% 4L == 0L & y %% 100L != 0L) | y %% 400L == 0L
  d + (!leap & d > 59L)
}

#' Climatology for every column of x (time x pixel, complete, no NA).
#' Returns list(seas, thresh), each 366 x ncol(x).
mhw_clim <- function(x, dates, baseline, window_half = 5L, pctile = 90,
                     smooth_width = 31L) {
  x <- as.matrix(x)
  baseline <- as.Date(baseline)
  inb <- dates >= baseline[1] & dates <= baseline[2]
  yr <- as.integer(format(dates[inb], "%Y"))
  years <- as.integer(format(baseline[1], "%Y")):as.integer(format(baseline[2], "%Y"))
  doy <- mhw_doy(dates[inb])
  xb <- x[inb, , drop = FALSE]
  if (anyNA(xb)) stop("mhw_clim: baseline must be complete (no NA)")
  ny <- length(years); np <- ncol(x)
  ## spread: row = doy, block per year; arr[doy, year, pixel]
  arr <- array(NA_real_, c(366L, ny, np))
  for (j in seq_len(ny)) {
    k <- which(yr == years[j])
    arr[doy[k], j, ] <- xb[k, , drop = FALSE]
  }
  ## Feb 29 fill for non-leap years (heatwaveR .NA2mean on rows 59:61)
  f29 <- is.na(arr[60L, , 1L])
  if (any(f29)) {
    arr[60L, f29, ] <- round((arr[59L, f29, , drop = FALSE] +
                              arr[61L, f29, , drop = FALSE]) / 2, 2)
  }
  if (anyNA(arr)) stop("mhw_clim: baseline years must be whole years")
  pad <- c(tail(seq_len(366L), window_half), seq_len(366L),
           head(seq_len(366L), window_half))
  seas <- thresh <- matrix(NA_real_, 366L, np)
  for (i in seq_len(366L)) {
    rows <- pad[i:(i + 2L * window_half)]
    ## (window row, year, pixel) flattened: one column per pixel
    pool <- matrix(arr[rows, , , drop = FALSE], ncol = np)
    seas[i, ] <- colMeans(pool)
    thresh[i, ] <- matrixStats::colQuantiles(pool, probs = pctile / 100,
                                             type = 7L, useNames = FALSE)
  }
  circ_mean <- function(m) {
    h <- smooth_width %/% 2L
    idx <- c(tail(seq_len(366L), h), seq_len(366L), head(seq_len(366L), h))
    cs <- rbind(0, matrixStats::colCumsums(m[idx, , drop = FALSE]))
    (cs[seq_len(366L) + smooth_width, , drop = FALSE] -
       cs[seq_len(366L), , drop = FALSE]) / smooth_width
  }
  list(seas = round(circ_mean(seas), 4L), thresh = round(circ_mean(thresh), 4L))
}

#' Event mask for one series: logical, TRUE on event days (incl. joined gaps).
mhw_event_mask <- function(exceed, min_duration = 5L, max_gap = 2L) {
  n <- length(exceed)
  r <- rle(exceed)
  ends <- cumsum(r$lengths); starts <- ends - r$lengths + 1L
  keep <- r$values & r$lengths >= min_duration
  dur <- logical(n)
  if (!any(keep)) return(dur)
  for (k in which(keep)) dur[starts[k]:ends[k]] <- TRUE
  r2 <- rle(dur)
  e2 <- cumsum(r2$lengths); s2 <- e2 - r2$lengths + 1L
  first_ev <- s2[which(r2$values)[1]]
  gap <- !r2$values & e2 > first_ev & r2$lengths <= max_gap
  ev <- dur
  for (k in which(gap)) ev[s2[k]:e2[k]] <- TRUE
  ev
}

#' Per-column events for a time x pixel chunk. Returns the event mask and
#' daily category (0 = no event; 1..4 = Hobday 2018 I-IV by
#' (x - seas) / (thresh - seas), event days below 1x counted as I).
mhw_detect <- function(x, dates, clim) {
  d <- mhw_doy(dates)
  seas <- clim$seas[d, , drop = FALSE]
  thresh <- clim$thresh[d, , drop = FALSE]
  x <- ifelse(is.na(x), seas, x)          # heatwaveR: NA -> seas
  exceed <- x > thresh
  ev <- matrix(FALSE, nrow(x), ncol(x))
  for (j in seq_len(ncol(x))) ev[, j] <- mhw_event_mask(exceed[, j])
  ratio <- (x - seas) / (thresh - seas)
  cat <- ifelse(ev, pmin(4L, pmax(1L, floor(ratio))), 0L)
  storage.mode(cat) <- "integer"
  list(event = ev, category = cat, anom = x - seas)
}

#' MHW pilot regions on the native MUR grid. A region is a pixel window
#' (origin -179.995, 89.995, 0.01 deg: pixel centres on whole hundredths)
#' plus the event windows its figures and per-pixel stats focus on.
#' lon0/lat0 are the NW pixel centre; nx/ny must be multiples of 50 (the
#' Zarr chunk). Each window: stats = dates for per-pixel stats, plot =
#' dates for the time-series panel.
mhw_regions <- list(
  tasman = list(
    title = "Tasman Sea", lon0 = 147, lat0 = -37, nx = 1000L, ny = 800L,
    windows = list(
      ev1516 = list(label = "2015/16", stats = c("2015-08-01", "2016-06-30"),
                    plot = c("2015-08-01", "2016-07-31"), map_label = "Aug 2015–Jun 2016"),
      ev2026 = list(label = "2026", stats = c("2026-01-01", "2026-12-31"),
                    plot = c("2026-01-01", "2026-12-31"), map_label = NULL))),
  wa = list(
    title = "Western Australia", lon0 = 106, lat0 = -21, nx = 1000L, ny = 1200L,
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
