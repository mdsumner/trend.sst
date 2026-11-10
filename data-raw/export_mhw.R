## data-raw/export_mhw.R -- marine heatwave snapshot for the Pages site.
## Manual snapshot (not part of export_site.sh): run after the region's
## pipeline (data-raw/mhw_*.R, validate/mhw_compare.R), commit docs/.
##   Rscript data-raw/export_mhw.R <region>
## Produces:
##   docs/data/mhw-regions.json        index of exported regions (merged)
##   docs/data/mhw-<region>.json       daily area-in-MHW by category, box
##                                     anomaly, event lists, annual days,
##                                     per-window summaries
##   docs/data/mhw-<region>-<win>.bin  Uint8, 2 planes of nx*ny, row 0 =
##                                     north, x fastest: [0] MHW days in
##                                     the window (255 = land), [1] peak
##                                     anomaly in 0.05 C steps (255 = land,
##                                     0 = no event)
##   docs/img/mhw_<region>_<win>.png   the static figures, copied
##
## GDAL-free (same libarrow clash as export_site.R): source the query layer
## and R/mhw.R directly.
library(heatwaveR)
source("R/series.R")
source("R/mhw.R")

args <- commandArgs(trailingOnly = TRUE)
region <- mhw_region(if (length(args)) args[1] else "tasman")
root <- region$root
out <- file.path("docs", "data"); img <- file.path("docs", "img")
dir.create(img, showWarnings = FALSE)
baseline <- c("2003-01-01", "2025-12-31")
classic <- c("1982-01-01", "2011-12-31")

px <- read.csv(file.path(root, "pixel_daily.csv")); px$date <- as.Date(px$date)
bx <- read.csv(file.path(root, "boxmean.csv")); bx$date <- as.Date(bx$date)
maps <- readRDS(file.path(root, "pixel_maps.rds"))
stopifnot(identical(px$date, bx$date))

clm <- ts2clm(data.frame(t = bx$date, temp = bx$mean), climatologyPeriod = baseline)
ev_box <- detect_event(clm)$event
box_days <- detect_event(clm, protoEvents = TRUE)$event

reg <- arrow::read_parquet("s2_registry.parquet")
b <- region$bbox
cin <- reg$cell[reg$lon >= b[["xmin"]] & reg$lon < b[["xmax"]] &
                reg$lat >= b[["ymin"]] & reg$lat < b[["ymax"]]]
so <- series_stats("sums/oisst", cin)
ev_oi <- detect_event(ts2clm(data.frame(t = as.Date(so$date), temp = so$mean),
                             climatologyPeriod = classic))$event

ev_rows <- function(e) lapply(seq_len(nrow(e)), function(i) list(
  start = format(as.Date(e$date_start[i])), end = format(as.Date(e$date_end[i])),
  peak = format(as.Date(e$date_peak[i])), days = e$duration[i],
  imax = round(e$intensity_max[i], 2), imean = round(e$intensity_mean[i], 2)))

## daily fractions as integers per 10,000 (compact, exact enough)
fr <- function(v) as.integer(round(1e4 * v / px$sumw))
q <- function(m, p) unname(round(stats::quantile(m, p, na.rm = TRUE), 2))

win_out <- list()
for (nm in names(region$windows)) {
  win <- region$windows[[nm]]; ws <- as.Date(win$stats)
  w <- px$date >= ws[1] & px$date <= ws[2]
  f <- px$sumw_mhw / px$sumw
  pk <- which(w)[which.max(f[w])]
  days <- maps[[paste0(nm, "_days")]]; anom <- maps[[paste0(nm, "_max_anom")]]
  ## planes: lon x lat matrices -> row 0 north, x fastest == column-major
  d8 <- ifelse(is.na(days), 255L, pmin(254L, as.integer(days)))
  a8 <- ifelse(is.na(days), 255L,
               ifelse(is.na(anom), 0L, pmin(254L, pmax(1L, as.integer(round(anom / 0.05))))))
  con <- file(file.path(out, sprintf("mhw-%s-%s.bin", region$name, nm)), "wb")
  writeBin(as.raw(c(d8, a8)), con); close(con)
  win_out[[length(win_out) + 1L]] <- list(
    key = nm, label = win$label, stats = win$stats, plot = win$plot,
    map_label = if (is.null(win$map_label)) {
      sprintf("%s–%s", format(ws[1], "%-d %b"), format(min(ws[2], max(px$date)), "%-d %b %Y"))
    } else win$map_label,
    partial = max(px$date) < ws[2],
    peak_frac = round(f[pk], 4), peak_date = format(px$date[pk]),
    peak_cat34 = round((px$sumw_cat3[pk] + px$sumw_cat4[pk]) / px$sumw[pk], 4),
    mean_frac = round(mean(f[w]), 4),
    box_days = sum(box_days[w]),
    days_q = q(days, c(.1, .5, .9)), anom_q = q(anom, c(.1, .5, .9)),
    max_cat = tabulate(maps[[paste0(nm, "_max_cat")]] + 1L, 5L),
    days_max = max(days, na.rm = TRUE))
  fig <- file.path(root, sprintf("mhw_%s_%s.png", region$name, nm))
  if (file.exists(fig)) file.copy(fig, file.path(img, basename(fig)), overwrite = TRUE)
}

annual_pix <- apply(maps$annual_days, 3, mean, na.rm = TRUE)
annual_box <- tapply(box_days, format(px$date, "%Y"), sum)
yrs <- names(annual_pix)

j <- list(
  name = region$name, title = region$title,
  bbox = list(lon = c(region$lon0, max(region$lon) + 0.01),
              lat = c(min(region$lat) - 0.01, region$lat0)),
  nx = region$nx, ny = region$ny, res = 0.01,
  baseline = baseline, classic = classic,
  generated = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  ocean_px = sum(!is.na(maps$n_events)),
  daily = list(start = format(min(px$date)), n = nrow(px),
               cat1 = fr(px$sumw_cat1), cat2 = fr(px$sumw_cat2),
               cat3 = fr(px$sumw_cat3), cat4 = fr(px$sumw_cat4),
               anom = round(px$sumw_anom / px$sumw, 2),
               box_mhw = as.integer(box_days)),
  events = list(mur = ev_rows(ev_box), oisst = ev_rows(ev_oi)),
  oisst_cells = length(cin), oisst_last = format(max(as.Date(so$date))),
  annual = list(years = as.integer(yrs), pixel_mean = round(unname(annual_pix), 1),
                box = as.integer(annual_box[yrs]),
                partial_last = format(max(px$date))),
  windows = win_out)
jsonlite::write_json(j, file.path(out, sprintf("mhw-%s.json", region$name)),
                     auto_unbox = TRUE, digits = NA, na = "null")

idx_path <- file.path(out, "mhw-regions.json")
idx <- if (file.exists(idx_path)) jsonlite::read_json(idx_path) else list()
idx[[region$name]] <- list(title = region$title, last = format(max(px$date)),
                           windows = vapply(win_out, `[[`, "", "key"))
idx <- idx[order(names(idx) != "tasman", names(idx))]
jsonlite::write_json(idx, idx_path, auto_unbox = TRUE, pretty = TRUE)
message(sprintf("exported %s: %s", region$name,
                paste(list.files(out, sprintf("^mhw-%s", region$name)), collapse = ", ")))
