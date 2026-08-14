## data-raw/backfill_oisst.R -- the whole OISST record, resumable.
## Small enough to run anywhere; the identical accumulate path scales to
## GHRSST on Setonix later (swap source, add mirai over dates).

devtools::load_all()  ## or library(trend.sst)

LEVEL <- 5L
registry <- build_registry(LEVEL)
arrow::write_parquet(registry, "s2_registry.parquet")

src <- oisst_source("oisstfiles.parquet")
src$files$dsn <- gsub("/vsicurl/https://", "/rdsi/PUBLIC/raad/data/", src$files$dsn)
## OISST is 1440 x 720: one band is fine, but keep the banded machinery
## identical to what GHRSST will use
if (!file.exists(file.path("mapping", src$name, "meta.rds"))) {
  build_mapping(src, registry, band_rows = 720L)
}

for (i in seq_len(nrow(src$files))) {
  res <- try(accumulate_date(src$files$dsn[i], src$files$date[i],
                             src, registry), silent = TRUE)
  if (inherits(res, "try-error")) {
    message(sprintf("FAIL %s", format(src$files$date[i])))
  }
  if (i %% 500 == 0) message(sprintf("%i / %i", i, nrow(src$files)))
}

## quick look: the ClimateReanalyzer-style series from cells
reg <- arrow::read_parquet("s2_registry.parquet")
cr_cells <- cells_latband(reg, -60, 60)
s <- series_stats(file.path("sums", "oisst"), cr_cells)
plot(s$date, s$mean, type = "l")
