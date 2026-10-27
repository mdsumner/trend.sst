## data-raw/backfill.R -- one runner for any source, serial or parallel.
## Replaces backfill_oisst.R and backfill_ghrsst.R so the OISST run
## exercises the identical code path GHRSST will use.
##
##   SST_SOURCE=oisst  SST_WORKERS=32 Rscript data-raw/backfill.R
##   SST_SOURCE=ghrsst SST_WORKERS=64 Rscript data-raw/backfill.R
##
## Run from the repo root (relative paths: mapping/, sums/, *.parquet).
## Resumable: file-per-date parquet, rerun to continue, failures write
## nothing. Mapping band files stay UNCOMPRESSED: every worker rereads
## them per date and the node page cache shares one copy; gzip would put
## decompression in the inner loop.

## arrow must initialize before anything loads GDAL's own libarrow,
## or arrow's filesystem registration fails with
## "register factory for scheme 'file'" (seen 2026-10-27 pulse check)
library(arrow)
library(trend.sst)

src_name <- Sys.getenv("SST_SOURCE", "oisst")
n_workers <- as.integer(Sys.getenv("SST_WORKERS", "1"))

## registry: read if present (it is committed), build once if not
if (file.exists("s2_registry.parquet")) {
  registry <- arrow::read_parquet("s2_registry.parquet")
} else {
  registry <- build_registry(5L)
  arrow::write_parquet(registry, "s2_registry.parquet")
}

src <- switch(src_name,
  oisst = oisst_source("oisstfiles.parquet"),
  ghrsst = ghrsst_source(),
  stop(sprintf("unknown SST_SOURCE '%s'", src_name)))

## optional site-local dsn rewrite (AAD raad filesystem); NEVER default:
## the vsicurl dsns in the catalog are the portable form
rewrite <- Sys.getenv("SST_DSN_REWRITE", "")   # e.g. "/vsicurl/https://=/rdsi/PUBLIC/raad/data/"
if (nzchar(rewrite)) {
  kv <- strsplit(rewrite, "=", fixed = TRUE)[[1]]
  src$files$dsn <- gsub(kv[1], kv[2], src$files$dsn, fixed = TRUE)
}

expected_dim <- switch(src_name, oisst = c(1440, 720), ghrsst = c(36000, 17999))
stopifnot(all(src$grid$dimension == expected_dim))

band_rows <- switch(src_name, oisst = 720L, ghrsst = 512L)
if (!file.exists(file.path("mapping", src$name, "meta.rds"))) {
  build_mapping(src, registry, band_rows = band_rows)
}
check_mapping(src)

out_path <- file.path("sums", src$name)
dir.create(out_path, recursive = TRUE, showWarnings = FALSE)
done <- file.path(out_path,
                  sprintf("%s.parquet", format(as.Date(src$files$date))))
todo <- which(!file.exists(done))
message(sprintf("[%s] %i of %i dates to do (%i workers)",
                src_name, length(todo), nrow(src$files), n_workers))

do_one <- function(dsn, date, source, registry) {
  res <- try(accumulate_date(dsn, date, source, registry), silent = TRUE)
  if (inherits(res, "try-error")) message(sprintf("FAIL %s", format(date)))
  invisible(NULL)
}

if (length(todo) > 0 && n_workers > 1) {
  library(mirai)
  daemons(n_workers)
  everywhere(library(trend.sst))
  res <- mirai_map(src$files[todo, c("dsn", "date")], do_one,
                   .args = list(source = src, registry = registry))[.progress]
  daemons(0)
} else if (length(todo) > 0) {
  for (i in todo) {
    do_one(src$files$dsn[i], src$files$date[i], src, registry)
    if (i %% 500 == 0) message(sprintf("%i / %i", i, nrow(src$files)))
  }
}

## no collation: the parquet dataset IS the product. Pulse check:
p <- try({
  s <- series_stats(out_path)
  message(sprintf("[%s] %i dates in sums; global mean %.2f .. %.2f",
                  src_name, nrow(s), min(s$mean), max(s$mean)))
}, silent = TRUE)
if (inherits(p, "try-error"))
  message("pulse check failed (non-fatal): ", attr(p, "condition")$message)
