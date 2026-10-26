## data-raw/export_site.R -- generate docs/data/* for the Pages site.
## Run against a local cache of the sums (see demo/downstream.R cache
## block) after each backfill; commit docs/ and Pages updates.
##   Rscript data-raw/export_site.R [cache_dir] [out_dir]
## Produces:
##   docs/data/status.json   store state per source (span, gaps, freshness)
##   docs/data/series.json   daily global + 60S-60N series per source
##   docs/data/cells.json    cell rings (slerp-densified) + per-cell metrics
##   docs/data/monthly.bin   Float32 cell x month mean matrix (cell-major)

library(trend.sst)
library(dplyr)

args <- commandArgs(trailingOnly = TRUE)
cache <- if (length(args) >= 1) args[1] else "cache"
out <- if (length(args) >= 2) args[2] else file.path("docs", "data")
dir.create(out, recursive = TRUE, showWarnings = FALSE)

reg <- arrow::read_parquet(file.path(cache, "s2_registry.parquet"))
paths <- list(oisst = file.path(cache, "sums", "oisst"),
              ghrsst = file.path(cache, "sums", "ghrsst"))
paths <- paths[vapply(paths, dir.exists, TRUE)]
prov_days <- c(oisst = 14L, ghrsst = 10L)

iso <- function(d) format(as.Date(d))

## ---------------------------------------------------------------- status
src_status <- function(p, pd) {
  d <- sort(as.Date(gsub("\\.parquet$", "", list.files(p, "\\.parquet$"))))
  full <- seq(min(d), max(d), by = "1 day")
  list(first = iso(min(d)), last = iso(max(d)), n = length(d),
       gaps = as.list(iso(setdiff(full, d))),
       provisional_days = pd)
}
status <- list(
  generated = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  provenance = list(gdal = tryCatch(
    gdalraster::gdal_version()[4], error = function(e) NA)),
  sources = lapply(names(paths), function(nm)
    src_status(paths[[nm]], prov_days[[nm]])) |> setNames(names(paths)))
jsonlite::write_json(status, file.path(out, "status.json"),
                     auto_unbox = TRUE, pretty = TRUE, na = "null")
message("status.json written")

## ---------------------------------------------------------------- series
cr_cells <- cells_latband(reg, -60, 60)
rnd <- function(x) round(x, 3)
series <- lapply(paths, function(p) {
  g <- series_stats(p)
  c <- series_stats(p, cr_cells)
  list(dates = iso(g$date), global = rnd(g$mean),
       cr = rnd(c$mean[match(g$date, c$date)]))
})
jsonlite::write_json(list(sources = series),
                     file.path(out, "series.json"),
                     auto_unbox = TRUE, digits = NA, na = "null")
message("series.json written")

## ------------------------------------------------- cells (OISST, warm-up)
p <- paths$oisst
YEARS <- 1982:2025
d0 <- as.Date(sprintf("%i-01-01", min(YEARS)))
d1 <- as.Date(sprintf("%i-12-31", max(YEARS)))

percell <- arrow::open_dataset(p) |>
  filter(date >= d0, date <= d1) |>
  group_by(cell) |>
  summarise(n = sum(n), sumw = sum(sumw), sumwx = sum(sumwx)) |>
  collect() |>
  mutate(mean = sumwx / sumw, w = sumw / n)   # w: mean per-day cell weight

ann <- arrow::open_dataset(p) |>
  filter(date >= d0, date <= d1) |>
  mutate(year = lubridate::year(date)) |>
  group_by(cell, year) |>
  summarise(sumw = sum(sumw), sumwx = sum(sumwx)) |>
  collect() |> mutate(m = sumwx / sumw)
trend <- ann |> group_by(cell) |>
  summarise(trend = if (dplyr::n() > 0.8 * length(YEARS))
    coef(lm(m ~ year))[2] * 10 else NA_real_, .groups = "drop")

last_d <- max(as.Date(gsub("\\.parquet$", "", list.files(p, "\\.parquet$"))))
a0 <- last_d - 364
recent <- arrow::open_dataset(p) |>
  filter(date >= a0) |>
  group_by(cell) |>
  summarise(sumw = sum(sumw), sumwx = sum(sumwx)) |>
  collect() |> mutate(recent = sumwx / sumw)
base <- arrow::open_dataset(p) |>
  filter(date >= as.Date("1982-01-01"), date <= as.Date("2011-12-31")) |>
  group_by(cell) |>
  summarise(sumw = sum(sumw), sumwx = sum(sumwx)) |>
  collect() |> mutate(base = sumwx / sumw)

percell <- percell |>
  left_join(trend, by = "cell") |>
  left_join(recent[c("cell", "recent")], by = "cell") |>
  left_join(base[c("cell", "base")], by = "cell") |>
  mutate(anom = recent - base) |>
  inner_join(reg[c("cell", "lon", "lat")], by = "cell") |>
  arrange(cell)

## slerp-densified ring per cell (edges are great-circle arcs)
xyz <- function(lon, lat) c(cos(lat * pi/180) * cos(lon * pi/180),
                            cos(lat * pi/180) * sin(lon * pi/180),
                            sin(lat * pi/180))
slerp <- function(a, b, n = 8) {
  t <- seq(0, 1, length.out = n)
  ang <- acos(max(-1, min(1, sum(a * b))))
  w1 <- sin((1 - t) * ang) / sin(ang); w2 <- sin(t * ang) / sin(ang)
  cbind(w1 * a[1] + w2 * b[1], w1 * a[2] + w2 * b[2], w1 * a[3] + w2 * b[3])
}
ring_of <- function(cell) {
  vs <- lapply(0:3, function(k) {
    pt <- s2::s2_cell_vertex(s2::s2_cell(cell), k)
    xyz(s2::s2_x(pt), s2::s2_y(pt))
  })
  pts <- do.call(rbind, lapply(1:4, function(i) slerp(vs[[i]], vs[[i %% 4 + 1]])))
  ll <- cbind(atan2(pts[, 2], pts[, 1]) * 180/pi,
              asin(pmax(-1, pmin(1, pts[, 3]))) * 180/pi)
  round(ll[!duplicated(round(ll, 5)), , drop = FALSE], 2)
}
rings <- lapply(percell$cell, ring_of)
message(sprintf("%i cell rings built", length(rings)))

## Spilhaus rendering of the same rings, via PROJ (+proj=spilhaus needs
## PROJ >= 9.6). Optional: silently absent if the local PROJ lacks it,
## and cells straddling the projection's seams are culled (the cuts run
## through land, so only a handful of coastal/Bering cells are lost).
spil <- tryCatch({
  s <- lapply(rings, function(r) {
    xy <- reproj::reproj_xy(r, "+proj=spilhaus", source = "EPSG:4326")
    if (!all(is.finite(xy))) return(NULL)
    seg <- sqrt(diff(xy[, 1])^2 + diff(xy[, 2])^2)
    if (max(seg) > 2e6) return(NULL)
    round(xy / 1000, 1)   # km for compact json
  })
  ok <- !vapply(s, is.null, TRUE)
  if (!any(ok)) NULL else {
    message(sprintf("spilhaus: %i of %i cells (%i seam-culled)",
                    sum(ok), length(s), sum(!ok)))
    s
  }
}, error = function(e) { message("spilhaus unavailable: ", conditionMessage(e)); NULL })

cells_out <- lapply(seq_len(nrow(percell)), function(i) {
  out <- list(id = percell$cell[i], ring = rings[[i]],
       mean = round(percell$mean[i], 2), trend = round(percell$trend[i], 3),
       anom = round(percell$anom[i], 2), w = round(percell$w[i], 1),
       lon = round(percell$lon[i], 2), lat = round(percell$lat[i], 2))
  if (!is.null(spil) && !is.null(spil[[i]])) out$sring <- spil[[i]]
  out
})

## ------------------------------------------- monthly matrix (cell-major)
mon <- arrow::open_dataset(p) |>
  filter(date >= d0) |>
  mutate(ym = lubridate::year(date) * 100L + lubridate::month(date)) |>
  group_by(cell, ym) |>
  summarise(sumw = sum(sumw), sumwx = sum(sumwx)) |>
  collect() |> mutate(m = sumwx / sumw)
yms <- sort(unique(mon$ym))
nm <- length(yms)
mat <- matrix(NaN, nrow(percell), nm)
mat[cbind(match(mon$cell, percell$cell), match(mon$ym, yms))] <- mon$m
con <- file(file.path(out, "monthly.bin"), "wb")
writeBin(as.numeric(t(mat)), con, size = 4, endian = "little")
close(con)
message(sprintf("monthly.bin: %i cells x %i months", nrow(mat), nm))

jsonlite::write_json(
  list(source = "oisst", years = range(YEARS),
       months = sprintf("%04i-%02i", yms %/% 100L, yms %% 100L),
       baseline = "1982-2011", cells = cells_out),
  file.path(out, "cells.json"), auto_unbox = TRUE, digits = NA, na = "null")
message("cells.json written")
