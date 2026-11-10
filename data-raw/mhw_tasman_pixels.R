## Marine heatwaves, Tasman pilot, step 4: per-pixel Hobday MHWs on MUR,
## baseline 2003-01-01..2025-12-31 (MUR-only, per the never-pool rule;
## OISST 1982-2011 is the paired classic reference, not mixed in).
## R/mhw.R is heatwaveR-exact (validate/mhw_parity.R).
##
## Outputs (cache/mhw/tasman/):
##   pixel_daily.csv  per date, additive over pixels (cos-lat weights):
##                    sumw ocean, sumw in MHW, sumw by category I-IV,
##                    sum w*anom (anom = sst - seas)
##   pixel_maps.rds   per pixel (lon x lat matrices, NA on land):
##                    annual MHW days (array lon x lat x year), event count,
##                    2015/16 window stats, 2026 stats
##
## Rscript data-raw/mhw_tasman_pixels.R [n_workers]

args <- commandArgs(trailingOnly = TRUE)
n_workers <- if (length(args)) as.integer(args[1]) else 24L
root <- file.path("cache", "mhw", "tasman")
store <- file.path(root, "sst.zarr")
baseline <- c("2003-01-01", "2025-12-31")

za <- jsonlite::read_json(file.path(store, "sst", ".zarray"))
ny <- za$shape[[1]]; nx <- za$shape[[2]]; nt <- za$shape[[3]]
cxy <- za$chunks[[1]]
rd <- function(name, what, n) readBin(memDecompress(readBin(
  file.path(store, name, "0"), "raw", 1e8), "gzip"), what, n = n)
dates <- as.Date(rd("time", "integer", nt), origin = "1970-01-01")
lat <- rd("lat", "double", ny); lon <- rd("lon", "double", nx)
years <- sort(unique(as.integer(format(dates, "%Y"))))

windows <- list(
  ev1516 = as.Date(c("2015-08-01", "2016-06-30")),
  ev2026 = as.Date(c("2026-01-01", "2026-12-31")))

do_chunk <- function(cy, cx, store, nt, cxy, lat, dates, baseline, windows) {
  b <- memDecompress(readBin(file.path(store, "sst", sprintf("%i.%i.0", cy, cx)),
                             "raw", 1e9), "gzip")
  v <- readBin(b, "integer", n = cxy * cxy * nt, size = 2L)
  m <- matrix(ifelse(v == -32768L, NA_real_, v * 0.001 + 25), nt)
  ## column j -> local (lon, lat): C order (lat, lon, time)
  jl <- seq_len(cxy * cxy) - 1L
  ix <- cx * cxy + jl %% cxy + 1L; iy <- cy * cxy + jl %/% cxy + 1L
  ocean <- colSums(is.na(m)) == 0L
  stopifnot(all(colSums(is.na(m)) %in% c(0L, nt)))  # constant land mask
  res <- list(ix = ix[ocean], iy = iy[ocean], n = sum(ocean))
  if (!any(ocean)) return(res)
  x <- m[, ocean, drop = FALSE]; rm(m)
  w <- cos(lat[res$iy] * pi / 180)
  clim <- mhw_clim(x, dates, baseline)
  det <- mhw_detect(x, dates, clim)
  ev <- det$event; ct <- det$category
  res$daily <- cbind(sumw = rep(sum(w), nt),
                     sumw_mhw = drop(ev %*% w),
                     sumw_cat1 = drop((ct == 1L) %*% w),
                     sumw_cat2 = drop((ct == 2L) %*% w),
                     sumw_cat3 = drop((ct == 3L) %*% w),
                     sumw_cat4 = drop((ct == 4L) %*% w),
                     sumw_anom = drop(det$anom %*% w))
  yr <- as.integer(format(dates, "%Y"))
  res$annual_days <- rowsum(ev * 1L, yr)          # year x pixel
  res$n_events <- colSums(ev[-1, , drop = FALSE] & !ev[-nt, , drop = FALSE]) + ev[1, ]
  for (nm in names(windows)) {
    k <- dates >= windows[[nm]][1] & dates <= windows[[nm]][2]
    e <- ev[k, , drop = FALSE]; a <- det$anom[k, , drop = FALSE]
    longest <- apply(e, 2, function(z) { r <- rle(z); max(0L, r$lengths[r$values]) })
    mx <- matrixStats::colMaxs(ifelse(e, a, -Inf))
    mx[!is.finite(mx)] <- NA                       # no event days in window
    res[[nm]] <- cbind(days = colSums(e), longest = longest, max_anom = mx,
                       max_cat = matrixStats::colMaxs(ct[k, , drop = FALSE]))
  }
  res$in_mhw_last <- ev[nt, ]
  res
}

chunks <- expand.grid(cy = seq_len(ny / cxy) - 1L, cx = seq_len(nx / cxy) - 1L)
message(sprintf("%i chunks, %i workers", nrow(chunks), n_workers))
mirai::daemons(n_workers)
mirai::everywhere({ setwd(wd); suppressMessages(devtools::load_all(quiet = TRUE)) },
                  wd = getwd())
t0 <- Sys.time()
out <- mirai::mirai_map(chunks, do_chunk,
                        .args = list(store = store, nt = nt, cxy = cxy, lat = lat,
                                     dates = dates, baseline = baseline,
                                     windows = windows))[.stop]
mirai::daemons(0)
message(sprintf("done in %.1f min", as.numeric(difftime(Sys.time(), t0, units = "mins"))))

## daily: additive over chunks
has <- vapply(out, function(r) r$n > 0, logical(1))
daily <- Reduce(`+`, lapply(out[has], `[[`, "daily"))
daily <- data.frame(date = dates, daily)
write.csv(daily, file.path(root, "pixel_daily.csv"), row.names = FALSE)

## maps: lon x lat, NA on land
blank <- matrix(NA_real_, nx, ny)
fill <- function(get) {
  mm <- blank
  for (r in out[has]) mm[cbind(r$ix, r$iy)] <- get(r)
  mm
}
annual <- array(NA_real_, c(nx, ny, length(years)), dimnames = list(NULL, NULL, years))
for (r in out[has]) {
  ad <- r$annual_days[as.character(years), , drop = FALSE]
  for (k in seq_along(years)) annual[cbind(r$ix, r$iy, k)] <- ad[k, ]
}
maps <- list(lon = lon, lat = lat, years = years, baseline = baseline,
             annual_days = annual,
             n_events = fill(function(r) r$n_events),
             in_mhw_last = fill(function(r) r$in_mhw_last),
             last_date = max(dates))
for (nm in names(windows)) for (s in c("days", "longest", "max_anom", "max_cat")) {
  maps[[paste(nm, s, sep = "_")]] <- fill(function(r) r[[nm]][, s])
}
saveRDS(maps, file.path(root, "pixel_maps.rds"))
message("ocean pixels: ", sum(vapply(out, `[[`, integer(1), "n")))
