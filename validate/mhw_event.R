## Marine heatwaves, step 4: Hobday et al. (2016) events on a region's
## box-mean MUR series, plus the OISST reference (S2 cells with centres in
## the box) on both baselines, for the region's focus windows.
## Reference events: tasman 2015/16 (Oliver et al. 2017, Nat Commun
## 8:16101); wa 2010/11 (Pearce & Feng 2013, J Mar Sys 111-112:139-156).
##
## Climatology: MUR-only baseline 2003-01-01..2025-12-31 (23 whole years;
## MUR starts 2002-06, so the 30-year convention is not available and we
## never borrow OISST's). heatwaveR defaults otherwise: 11-day window,
## 31-day smoothing, 90th percentile, >= 5 days, gaps <= 2 days joined.
##
## Sensitivity: "raw" vs "masked", where masked sets suspect days NA and
## lets ts2clm/detect_event interpolate (maxPadLength 3): the README's
## known-bad 2025-08-24..29, plus box-mean one-day glitches > 0.5 C off a
## centred 7-day running median (~8 sd of that residual).
##
## Rscript validate/mhw_event.R <region>

suppressMessages(devtools::load_all(quiet = TRUE))
library(heatwaveR)
args <- commandArgs(trailingOnly = TRUE)
region <- mhw_region(if (length(args)) args[1] else "tasman")
root <- region$root
d <- read.csv(file.path(root, "boxmean.csv"))
d$date <- as.Date(d$date)

dev <- d$mean - stats::runmed(d$mean, 7)
suspect <- abs(dev) > 0.5 |
  (d$date >= as.Date("2025-08-24") & d$date <= as.Date("2025-08-29"))
message("masked dates: ", paste(format(d$date[suspect]), collapse = " "))

baseline <- c("2003-01-01", "2025-12-31")
run <- function(temp) {
  ts <- data.frame(t = d$date, temp = temp)
  clm <- ts2clm(ts, climatologyPeriod = baseline, maxPadLength = 3)
  detect_event(clm, maxPadLength = 3)
}
res <- list(raw = run(d$mean), masked = run(replace(d$mean, suspect, NA)))

summarise_events <- function(ev, label) {
  e <- ev$event
  cat(sprintf("\n== %s: %i events, %i days in MHW conditions\n", label,
              nrow(e), sum(e$duration)))
  cols <- c("date_start", "date_peak", "date_end", "duration",
            "intensity_mean", "intensity_max", "intensity_cumulative")
  cat("longest 6:\n")
  print(e[order(-e$duration), cols][1:6, ], digits = 3, row.names = FALSE)
  for (w in region$windows) print_window(e, w)
  invisible(e)
}
print_window <- function(e, w) {
  cols <- c("date_start", "date_peak", "date_end", "duration",
            "intensity_mean", "intensity_max", "intensity_cumulative")
  s <- as.Date(w$stats)
  hit <- e[e$date_end >= s[1] & e$date_start <= s[2], cols]
  cat(sprintf("events overlapping %s (%s..%s): %i, %i days\n", w$label, s[1], s[2],
              nrow(hit), sum(hit$duration)))
  if (nrow(hit)) print(hit, digits = 3, row.names = FALSE)
}
ev <- Map(summarise_events, res, names(res))

## OISST reference: S2 cells with centres in the box, both baselines
reg <- arrow::read_parquet("s2_registry.parquet")
b <- region$bbox
cin <- reg$cell[reg$lon >= b[["xmin"]] & reg$lon < b[["xmax"]] &
                reg$lat >= b[["ymin"]] & reg$lat < b[["ymax"]]]
so <- series_stats("sums/oisst", cin)
cat(sprintf("\n== OISST, %i cells with centres in box, data to %s\n", length(cin),
            format(max(as.Date(so$date)))))
for (bl in list(c("1982-01-01", "2011-12-31"), baseline)) {
  eo <- detect_event(ts2clm(data.frame(t = as.Date(so$date), temp = so$mean),
                            climatologyPeriod = bl))$event
  cat(sprintf("-- baseline %s..%s\n", bl[1], bl[2]))
  for (w in region$windows) print_window(eo, w)
}

saveRDS(res, file.path(root, "mhw_boxmean.rds"))
