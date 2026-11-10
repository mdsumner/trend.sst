## Marine heatwaves, step 3: a region's box-mean daily series from the
## per-date window files, as sufficient statistics (same schema as the
## sums: n, sumw, sumwx, sumwx2, cos-latitude weights), so the mean and
## spatial variance are exact arithmetic downstream.
##
## Rscript data-raw/mhw_boxmean.R <region>  -> cache/mhw/<region>/boxmean.csv

source("R/mhw.R")
args <- commandArgs(trailingOnly = TRUE)
region <- mhw_region(if (length(args)) args[1] else "tasman")
root <- region$root
files <- sds::ghrsst()
dates <- as.Date(files$date)
paths <- file.path(root, "dates", sprintf("%s.i16", format(dates)))
stopifnot(all(file.exists(paths)))

lat <- region$lat
## pixel order is x fastest, so latitude repeats per row of nx
w <- rep(cos(lat * pi / 180), each = region$nx)

stats_one <- function(path, w, npx) {
  v <- readBin(path, "integer", n = npx + 1L, size = 2L)
  stopifnot(length(v) == npx)
  fin <- v != -32768L
  x <- v[fin] * 0.001 + 25
  ww <- w[fin]
  c(n = sum(fin), sumw = sum(ww), sumwx = sum(ww * x), sumwx2 = sum(ww * x * x))
}

mirai::daemons(16L)
res <- mirai::mirai_map(paths, stats_one,
                        .args = list(w = w, npx = region$nx * region$ny))[.stop]
mirai::daemons(0)

out <- data.frame(date = dates, do.call(rbind, res))
out$mean <- out$sumwx / out$sumw
out$sd <- sqrt(pmax(0, out$sumwx2 / out$sumw - out$mean^2))
write.csv(out, file.path(root, "boxmean.csv"), row.names = FALSE)
message(sprintf("%i dates; n ocean pixels: %s", nrow(out),
                paste(unique(out$n), collapse = ", ")))
