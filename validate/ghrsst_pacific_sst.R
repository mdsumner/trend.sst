#!/usr/bin/env Rscript
## Pacific mean SST from GHRSST COGs, one value per date.
## File-per-date cache: rerun any time, only missing dates are computed,
## failures write nothing and are picked up on the next run.

library(mirai)

## leave headroom on the 128-cpu node (network-bound anyway)
n_workers <- as.integer(Sys.getenv("SST_WORKERS", "96"))

files <- sds::ghrsst()

cache_dir <- "ghrsst_pacific_cache"
dir.create(cache_dir, showWarnings = FALSE)
files$cache <- file.path(cache_dir, paste0(format(files$date, "%Y-%m-%d"), ".rds"))

## self-contained so it ships cleanly to daemons (no globals needed)
do_one <- function(date, source, cache) {
  if (file.exists(cache)) return(invisible(NULL))
  vapour::vapour_set_config("GDAL_DISABLE_READDIR_ON_OPEN", "EMPTY_DIR")
  #dsn <- sprintf("vrt://%s?ovr=-1", source)
  val <- try({
    v <- vapour::gdal_raster_data(sprintf("vrt://%s?projwin=-179.995,60,180.005,-60&ovr=-1", source[1]),
                           target_crs = "+proj=laea +lon_0=-155 +lat_0=0", target_ext = c(-1, 1, -1, 1)  * 6378137,
                           target_res = c(25000, 25000), resample = "average")[[1]]
    mean(v, na.rm = TRUE)
  }, silent = TRUE)
  if (inherits(val, "try-error") || !is.finite(val)) {
    return(invisible(NULL))
  }
  ## atomic write so a walltime kill never leaves a corrupt cache file
  tmp <- tempfile(tmpdir = dirname(cache), fileext = ".tmp")
  saveRDS(list(date = date, pacific_mean = val), tmp)
  file.rename(tmp, cache)
  invisible(NULL)
}

todo <- which(!file.exists(files$cache))
message(sprintf("%i of %i dates to do", length(todo), nrow(files)))

## optional batch cap per run, uncomment to limit
# todo <- head(todo, 2000)

if (length(todo) > 0) {
  daemons(n_workers)
  on.exit(daemons(0), add = TRUE)
  ## mirai_map over the data frame passes columns as named args, row by row
  res <- mirai_map(files[todo, c("date", "source", "cache")], do_one)[.progress]
  daemons(0)
}

## collate whatever is done so far (partial runs still produce output)
done <- files$cache[file.exists(files$cache)]
vals <- lapply(done, readRDS)
d <- data.frame(date = as.Date(vapply(vals, function(x) format(x$date), "")),
                pacific_mean = vapply(vals, function(x) x$pacific_mean, 0.0))
d <- d[order(d$date), ]
write.csv(d, "ghrsst_pacific_sst.csv", row.names = FALSE)
message(sprintf("wrote %i rows to ghrsst_pacific_sst.csv", nrow(d)))
