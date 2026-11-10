## Marine heatwaves, step 1: fetch a region's window (R/mhw.R mhw_region()) from
## every MUR COG as raw Int16 (scale 0.001, offset 25 -> Celsius; nodata
## -32768). One file per date, atomic write, rerun-to-resume: existing
## files are skipped, failed dates just retry next run.
##
## Window is in native pixel space (no resampling). The MUR geotransform
## has its origin at (-179.995, 89.995), so pixel centres sit on whole
## hundredths: col j (0-based) centre = -179.99 + 0.01 j,
##                row i (0-based) centre =   89.99 - 0.01 i.
## e.g. tasman: xoff 32699, yoff 12699, 1000 x 800 -> centres lon
## 147.00..156.99, lat -37.00..-44.99.
##
## Known-bad dates are NOT masked here: the store is raw, flagging happens
## at analysis time (same rule as the sums).
##
## Rscript data-raw/mhw_fetch.R <region> [n_workers]

source("R/mhw.R")
args <- commandArgs(trailingOnly = TRUE)
region <- mhw_region(if (length(args)) args[1] else "tasman")
n_workers <- if (length(args) > 1) as.integer(args[2]) else 24L
out_dir <- file.path(region$root, "dates")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

files <- sds::ghrsst()
files$date <- as.Date(files$date)
files$out <- file.path(out_dir, sprintf("%s.i16", format(files$date)))
todo <- files[!file.exists(files$out), ]
message(sprintf("%i dates, %i to fetch, %i workers",
                nrow(files), nrow(todo), n_workers))
if (!nrow(todo)) quit(save = "no")

fetch_one <- function(dsn, out, region) {
  gdalraster::set_config_option("GDAL_DISABLE_READDIR_ON_OPEN", "EMPTY_DIR")
  gdalraster::set_config_option("GDAL_HTTP_CONNECTTIMEOUT", "30")
  gdalraster::set_config_option("GDAL_HTTP_TIMEOUT", "120")
  gdalraster::set_config_option("GDAL_HTTP_MAX_RETRY", "3")
  gdalraster::set_config_option("GDAL_HTTP_RETRY_DELAY", "5")
  ds <- new(gdalraster::GDALRaster, dsn)
  on.exit(ds$close())
  stopifnot(ds$getRasterXSize() == 36000L, ds$getRasterYSize() == 17999L,
            isTRUE(all.equal(ds$getGeoTransform(),
                             c(-179.995, 0.01, 0, 89.995, 0, -0.01))),
            ds$getScale(1) == 0.001, ds$getOffset(1) == 25)
  v <- ds$read(1L, region$xoff, region$yoff, region$nx, region$ny,
               region$nx, region$ny)
  stopifnot(length(v) == region$nx * region$ny)
  ## gdalraster hands nodata back as NA; writeBin(size = 2) would truncate
  ## NA_integer_ to 0 (= 25 C), so restore the sentinel explicitly
  v <- as.integer(v)
  v[is.na(v)] <- -32768L
  tmp <- paste0(out, ".tmp")
  writeBin(v, tmp, size = 2L)
  file.rename(tmp, out)
}

mirai::daemons(n_workers)
t0 <- Sys.time()
res <- mirai::mirai_map(todo[c("source", "out")],
                        function(source, out) fetch_one(source, out, region),
                        fetch_one = fetch_one, region = region)[]
mirai::daemons(0)

bad <- vapply(res, mirai::is_error_value, logical(1))
message(sprintf("done in %.1f min: %i ok, %i failed",
                as.numeric(difftime(Sys.time(), t0, units = "mins")),
                sum(!bad), sum(bad)))
if (any(bad)) {
  writeLines(format(todo$date[bad]), file.path(dirname(out_dir), "failed.txt"))
  print(head(res[bad], 3))
}
