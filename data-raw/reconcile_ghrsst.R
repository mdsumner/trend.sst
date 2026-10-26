## data-raw/reconcile_ghrsst.R -- align the sums with the finalised COGs.
## The cogger now publishes a daily STAC GeoParquet index with per-date
## provenance (ghrsst:status, updated, checksums). Reconciliation is one
## join: any date whose item was updated AFTER we accumulated it is
## stale; delete its parquet and the ordinary resumable backfill heals.
##
## Run from the repo root on setonix AFTER restoring sums/ from acacia:
##   rclone copy pawsey1197:aad-derived/trend-sst/sums/ sums/
##   rclone copy pawsey1197:aad-derived/trend-sst/mapping/ mapping/

library(dplyr)

## 1. the cogger's index (rebuilt daily by ghrsst-lambda-parquet-daily)
idx_url <- "https://data.source.coop/ausantarctic/ghrsst-mur-v2/ghrsst-mur-v2.parquet"
idx_file <- "ghrsst-mur-v2-index.parquet"
download.file(idx_url, idx_file, mode = "wb")
idx <- arrow::read_parquet(idx_file)
print(names(idx))   # inspect once; column names below may need ADJUSTing

## STAC GeoParquet conventions; ADJUST if the printed names differ
stac <- tibble::tibble(
  date = as.Date(idx[["datetime"]]),
  status = idx[["ghrsst:status"]],
  updated = as.POSIXct(idx[["updated"]], tz = "UTC"))

## 2. what we hold, and when we computed it (file mtime = accumulated-at;
##    rclone copy preserves mtimes, so restored files keep their times)
sums_dir <- file.path("sums", "ghrsst")
f <- list.files(sums_dir, pattern = "\\.parquet$", full.names = TRUE)
held <- tibble::tibble(
  date = as.Date(gsub("\\.parquet$", "", basename(f))),
  path = f,
  computed = file.info(f)$mtime)

r <- full_join(stac, held, by = "date") |> arrange(date)

## 3. the verdicts
r <- r |> mutate(verdict = case_when(
  is.na(path) ~ "missing",                       # new date, ordinary todo
  is.na(status) ~ "not_indexed",                 # we hold a date the index lacks: investigate
  updated > computed ~ "stale",                  # re-COGged after we ran
  status != "final" ~ "provisional",             # current but NRT-derived; will finalise
  TRUE ~ "ok"))
print(count(r, verdict))
print(r |> filter(verdict == "stale") |> summarise(n = dplyr::n(),
      from = min(date), to = max(date)))

## 4. snapshot the stale rows BEFORE deletion, so healed values can be
##    diffed against what the preliminary analyses gave us
stale <- r |> filter(verdict == "stale")
if (nrow(stale) > 0) {
  old <- arrow::open_dataset(sums_dir) |>
    filter(date %in% stale$date) |> collect()
  arrow::write_parquet(old, sprintf("sums_pre_reconcile_%s.parquet", Sys.Date()))
  file.remove(stale$path)
  message(sprintf("removed %i stale date files; snapshot kept", nrow(stale)))
}

## 5. heal: the ordinary resumable run recomputes stale + missing
##      SST_SOURCE=ghrsst SST_WORKERS=42 sbatch --export=ALL data-raw/backfill.sh
##    then push (copy re-uploads changed files, deletes nothing; if the
##    bucket path uses --immutable, delete the stale objects explicitly
##    first -- revisions are loud, named operations)
##
## 6. afterwards, the healing check (2003-11 is the control: final since
##    2015's reprocessing, should be byte-stable):
# new <- arrow::open_dataset(sums_dir) |> filter(date %in% stale$date) |> collect()
# cmp <- inner_join(
#   old |> group_by(date) |> summarise(before = sum(sumwx) / sum(sumw)),
#   new |> group_by(date) |> summarise(after = sum(sumwx) / sum(sumw)),
#   by = "date") |> mutate(diff = after - before)
# cmp |> filter(abs(diff) > 0.01)   # expect 2025-08-24..29 here if healed
