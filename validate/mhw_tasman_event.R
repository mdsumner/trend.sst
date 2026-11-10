## Marine heatwaves, Tasman pilot, step 3b: Hobday et al. (2016) events on
## the box-mean MUR series, checked against the 2015/16 Tasman Sea MHW
## (Oliver et al. 2017, Nat Commun 8:16101).
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
## Rscript validate/mhw_tasman_event.R

library(heatwaveR)
root <- file.path("cache", "mhw", "tasman")
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
  ## the 2015/16 event: whichever event spans the 2015-12-31 peak season
  hit <- e[e$date_start <= as.Date("2016-01-15") & e$date_end >= as.Date("2015-12-15"), cols]
  cat("event covering Dec 2015/Jan 2016:\n")
  print(hit, digits = 3, row.names = FALSE)
  ## everything Sep 2015 - Jun 2016, to see fragmentation
  frag <- e[e$date_end >= as.Date("2015-08-01") & e$date_start <= as.Date("2016-06-30"), cols]
  cat("all events Aug 2015 - Jun 2016:\n")
  print(frag, digits = 3, row.names = FALSE)
  invisible(e)
}
ev <- Map(summarise_events, res, names(res))

saveRDS(res, file.path(root, "mhw_boxmean.rds"))
