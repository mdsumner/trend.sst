## Parity: R/mhw.R (vectorised) vs heatwaveR ts2clm() + detect_event() on
## the Tasman box-mean series and random ocean pixels from sst.zarr.
## Pass = identical seas/thresh (after heatwaveR's 4-dp rounding) and
## identical event-day masks.
##
## Rscript validate/mhw_parity.R [n_pixels]

suppressMessages(devtools::load_all(quiet = TRUE))
library(heatwaveR)
args <- commandArgs(trailingOnly = TRUE)
n_px <- if (length(args)) as.integer(args[1]) else 40L
root <- file.path("cache", "mhw", "tasman")
store <- file.path(root, "sst.zarr")
baseline <- c("2003-01-01", "2025-12-31")

za <- jsonlite::read_json(file.path(store, "sst", ".zarray"))
nt <- za$shape[[3]]; cxy <- za$chunks[[1]]
dates <- as.Date(readBin(memDecompress(readBin(file.path(store, "time", "0"),
  "raw", 1e8), "gzip"), "integer", n = nt), origin = "1970-01-01")

read_chunk <- function(cy, cx) {
  b <- memDecompress(readBin(file.path(store, "sst", sprintf("%i.%i.0", cy, cx)),
                             "raw", 1e9), "gzip")
  v <- readBin(b, "integer", n = cxy * cxy * nt, size = 2L)
  v <- ifelse(v == -32768L, NA_real_, v * 0.001 + 25)
  matrix(v, nt)   # column = lon_local + cxy * lat_local (C order)
}

hw_ref <- function(temp) {
  clm <- ts2clm(data.frame(t = dates, temp = temp), climatologyPeriod = baseline)
  ev <- detect_event(clm, protoEvents = TRUE)
  list(seas = clm$seas, thresh = clm$thresh, event = ev$event)
}

compare <- function(x, label) {
  ref <- hw_ref(x)
  clim <- mhw_clim(matrix(x), dates, baseline)
  det <- mhw_detect(matrix(x), dates, clim)
  d <- mhw_doy(dates)
  c(label = label,
    d_seas = max(abs(clim$seas[d, 1] - ref$seas)),
    d_thresh = max(abs(clim$thresh[d, 1] - ref$thresh)),
    event_days_ref = sum(ref$event), event_days_ours = sum(det$event[, 1]),
    mask_mismatch = sum(ref$event != det$event[, 1]))
}

box <- read.csv(file.path(root, "boxmean.csv"))
stopifnot(identical(as.Date(box$date), dates))
out <- list(compare(box$mean, "boxmean"))

set.seed(20151231)
nchy <- za$shape[[1]] / cxy; nchx <- za$shape[[2]] / cxy
picked <- 0L
while (picked < n_px) {
  cy <- sample(nchy, 1) - 1L; cx <- sample(nchx, 1) - 1L
  m <- read_chunk(cy, cx)
  ocean <- which(colSums(is.na(m)) == 0)
  if (!length(ocean)) next
  j <- ocean[sample.int(length(ocean), 1)]
  out[[length(out) + 1L]] <- compare(m[, j], sprintf("px %i.%i:%i", cy, cx, j))
  picked <- picked + 1L
}
res <- as.data.frame(do.call(rbind, out))
for (k in names(res)[-1]) res[[k]] <- as.numeric(res[[k]])
print(res, digits = 3, row.names = FALSE)
cat(sprintf("\nmax |d seas| %.2g, max |d thresh| %.2g, total mask mismatches %i over %i series\n",
            max(res$d_seas), max(res$d_thresh), sum(res$mask_mismatch), nrow(res)))
