## Sources: a source is a name, a catalog of (date, dsn), and the native
## grid signature (dimension, extent) that the mapping is built against.
## The grid signature is the contract between mapping and daily reads:
## accumulate_date() refuses to run if they disagree.

grid_from_dsn <- function(dsn) {
  info <- vapour::vapour_raster_info(dsn)
  list(dimension = info$dimension, extent = info$extent,
       projection = info$projection)
}

#' OISST daily files (0.25 deg, lon 0..360, 1981-09 onward).
#' Catalog built by data-raw/oisstfiles.R: full grid, sst subdataset,
#' unscaled Float32 (no projwin -- the whole grid is the product).
oisst_source <- function(catalog = "oisstfiles.parquet") {
  files <- arrow::read_parquet(catalog)
  list(name = "oisst", files = files[c("date", "dsn")],
       grid = grid_from_dsn(files$dsn[1]))
}

#' GHRSST MUR COGs (0.01 deg, 2002-06 onward).
ghrsst_source <- function() {
  files <- sds::ghrsst()
  files$dsn <- files$source
  list(name = "ghrsst", files = files[c("date", "dsn")],
       grid = grid_from_dsn(files$dsn[1]))
}

#' Read a contiguous block of rows (GDAL order, row 1 = top) at native
#' resolution: a window read, no reprojection.
read_rows <- function(dsn, rows, grid) {
  dm <- grid$dimension
  ex <- grid$extent
  resx <- (ex[2] - ex[1]) / dm[1]
  resy <- (ex[4] - ex[3]) / dm[2]
  ymax <- ex[4] - (min(rows) - 1) * resy
  ymin <- ex[4] - max(rows) * resy
  vapour::gdal_raster_data(dsn,
    target_ext = c(ex[1], ex[2], ymin, ymax),
    target_res = c(resx, resy),
    resample = "near")[[1]]
}
