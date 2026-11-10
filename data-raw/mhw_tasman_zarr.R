## Marine heatwaves, Tasman pilot, step 2b: transpose the per-date window
## files (data-raw/mhw_tasman_fetch.R) into a time-chunked Zarr v2 store,
## so each pixel's full series is contiguous inside one chunk.
##
## Hand-written Zarr v2 (Rarr cannot write int16): zlib codec (R's
## memCompress "gzip" is RFC 1950 zlib, which is what numcodecs Zlib
## expects), C order, xarray-style _ARRAY_DIMENSIONS.
##
##   sst  int16 (lat, lon, time), chunks (50, 50, ntime),
##        fill -32768, scale_factor 0.001, add_offset 25 -> Celsius
##   time int32 days since 1970-01-01;  lat, lon float64 pixel centres
##
## Raw, unmasked: known-bad dates are flagged at analysis time.
##
## Rscript data-raw/mhw_tasman_zarr.R

region <- list(name = "tasman", xoff = 32699L, yoff = 12699L,
               nx = 1000L, ny = 800L)
root <- file.path("cache", "mhw", region$name)
date_dir <- file.path(root, "dates")
store <- file.path(root, "sst.zarr")
chunk_xy <- 50L

files <- sds::ghrsst()
dates <- as.Date(files$date)
paths <- file.path(date_dir, sprintf("%s.i16", format(dates)))
missing <- !file.exists(paths)
if (any(missing)) stop(sprintf("%i dates not fetched yet, e.g. %s",
                               sum(missing), format(dates[which(missing)[1]])))
stopifnot(!anyDuplicated(dates), all(diff(dates) == 1))

nt <- length(dates); npx <- region$nx * region$ny
message(sprintf("loading %i dates x %i pixels", nt, npx))
## (time, pixel), pixel = x + nx * y with x fastest: column-major memory
## is then C order for (lat, lon, time)
m <- matrix(0L, nt, npx)
for (k in seq_len(nt)) {
  v <- readBin(paths[k], "integer", n = npx + 1L, size = 2L)
  stopifnot(length(v) == npx)
  m[k, ] <- v
}

json <- function(x) jsonlite::toJSON(x, auto_unbox = TRUE, digits = NA,
                                     pretty = TRUE, null = "null")
write_array <- function(name, shape, chunks, dtype, fill, attrs, chunk_fun) {
  dir <- file.path(store, name)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(json(list(zarr_format = 2L, shape = shape, chunks = chunks,
                       dtype = dtype, order = "C", fill_value = fill,
                       filters = NULL, dimension_separator = ".",
                       compressor = list(id = "zlib", level = 6L))),
             file.path(dir, ".zarray"))
  writeLines(json(attrs), file.path(dir, ".zattrs"))
  chunk_fun(dir)
}
put_chunk <- function(dir, key, bytes) {
  writeBin(memCompress(bytes, type = "gzip"), file.path(dir, key))
}

unlink(store, recursive = TRUE)
dir.create(store, recursive = TRUE)
writeLines(json(list(zarr_format = 2L)), file.path(store, ".zgroup"))
writeLines(json(list(
  title = "GHRSST MUR L4 v04.1 analysed_sst, Tasman window, time-chunked",
  source = "https://data.source.coop/ausantarctic/ghrsst-mur-v2/ analysed_sst COGs (sds::ghrsst())",
  window = region, history = sprintf("data-raw/mhw_tasman_zarr.R %s",
                                     format(Sys.time(), tz = "UTC")))),
  file.path(store, ".zattrs"))

lon <- round(-179.99 + 0.01 * (region$xoff + seq_len(region$nx) - 1L), 2)
lat <- round(89.99 - 0.01 * (region$yoff + seq_len(region$ny) - 1L), 2)
write_array("lon", region$nx, region$nx, "<f8", NULL,
            list(`_ARRAY_DIMENSIONS` = list("lon"), units = "degrees_east"),
            function(dir) put_chunk(dir, "0", writeBin(lon, raw())))
write_array("lat", region$ny, region$ny, "<f8", NULL,
            list(`_ARRAY_DIMENSIONS` = list("lat"), units = "degrees_north"),
            function(dir) put_chunk(dir, "0", writeBin(lat, raw())))
write_array("time", nt, nt, "<i4", NULL,
            list(`_ARRAY_DIMENSIONS` = list("time"),
                 units = "days since 1970-01-01", calendar = "proleptic_gregorian"),
            function(dir) put_chunk(dir, "0", writeBin(as.integer(dates), raw())))

stopifnot(region$nx %% chunk_xy == 0L, region$ny %% chunk_xy == 0L)
write_array("sst", c(region$ny, region$nx, nt), c(chunk_xy, chunk_xy, nt),
            "<i2", -32768L,
            list(`_ARRAY_DIMENSIONS` = list("lat", "lon", "time"),
                 scale_factor = 0.001, add_offset = 25, units = "degree_Celsius",
                 known_bad_dates = c("2003-11 pair", "2025-08-24..2025-08-29")),
            function(dir) {
              for (cy in seq_len(region$ny / chunk_xy) - 1L) {
                for (cx in seq_len(region$nx / chunk_xy) - 1L) {
                  x <- cx * chunk_xy + seq_len(chunk_xy) - 1L
                  y <- cy * chunk_xy + seq_len(chunk_xy) - 1L
                  ## y outer, x inner, matching C order (lat, lon, time)
                  px <- as.vector(outer(x, region$nx * y, "+")) + 1L
                  put_chunk(dir, sprintf("%i.%i.0", cy, cx),
                            writeBin(as.vector(m[, px]), raw(), size = 2L))
                }
                message(sprintf("chunk row %i/%i", cy + 1L, region$ny / chunk_xy))
              }
            })
message("wrote ", store)
