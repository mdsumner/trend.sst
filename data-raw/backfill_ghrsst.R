## data-raw/backfill_ghrsst.R -- the GHRSST record on Setonix, resumable.
## Same semantics as OISST: file-per-date parquet, rerun to resume,
## failures write nothing. Run under sbatch (see backfill_ghrsst.sh).
##
## Mapping I/O design: band files are stored UNCOMPRESSED on /scratch
## (~8 GB total). Every worker readRDS()es the same 36 files per date,
## but after the first pass they live in the node page cache, so reads
## are memory-speed and one copy is shared across all daemons. Do not
## gzip them: per-read decompression x 36 bands x thousands of dates
## would dominate the run.

library(mirai)
library(trend.sst)   ## R CMD INSTALL the repo on setonix first

n_workers <- as.integer(Sys.getenv("SST_WORKERS", "64"))

registry <- arrow::read_parquet("s2_registry.parquet")
src <- ghrsst_source()
stopifnot(identical(src$grid$dimension, c(36000L, 17999L)))

## one-off mapping build (serial, order 15-30 min; a coffee, not a job)
if (!file.exists(file.path("mapping", src$name, "meta.rds"))) {
  build_mapping(src, registry, band_rows = 512L)
}
check_mapping(src)

out_path <- file.path("sums", src$name)
dir.create(out_path, recursive = TRUE, showWarnings = FALSE)
done <- file.path(out_path,
                  sprintf("%s.parquet", format(as.Date(src$files$date))))
todo <- which(!file.exists(done))
message(sprintf("%i of %i dates to do", length(todo), nrow(src$files)))

do_one <- function(dsn, date, source, registry) {
  res <- try(accumulate_date(dsn, date, source, registry), silent = TRUE)
  if (inherits(res, "try-error")) message(sprintf("FAIL %s", format(date)))
  invisible(NULL)
}

if (length(todo) > 0) {
  daemons(n_workers)
  on.exit(daemons(0), add = TRUE)
  everywhere(library(trend.sst))
  res <- mirai_map(src$files[todo, c("dsn", "date")], do_one,
                   .args = list(source = src, registry = registry))[.progress]
  daemons(0)
}

## no collation step: the parquet dataset IS the product. Quick pulse:
s <- series_stats(out_path)
message(sprintf("%i dates in sums; global mean range %.2f .. %.2f",
                nrow(s), min(s$mean), max(s$mean)))
