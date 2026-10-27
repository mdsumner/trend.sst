## data-raw/export_site.R -- generate docs/data/* for the Pages site.
## Run against a local cache of the sums (see demo/downstream.R cache
## block) after each backfill; commit docs/ and Pages updates.
##   Rscript data-raw/export_site.R [cache_dir] [out_dir]
## Produces:
##   docs/data/status.json   store state per source (span, gaps, freshness)
##   docs/data/series.json   daily global + 60S-60N series per source
##   docs/data/cells.json    cell rings (slerp-densified) + per-cell metrics
##   docs/data/monthly.bin   Float32 cell x month mean matrix (cell-major)

## The exporter is deliberately GDAL-FREE: library(trend.sst) pulls in
## vapour and so GDAL's bundled libarrow, which clashes with R arrow's
## filesystem registration ("register factory for scheme 'file'",
## jobs 51664079+). Nothing here reads a raster, so source the
## query-layer functions directly and never load GDAL at all.
library(arrow)
library(dplyr)
source("R/cells.R")    # cells_latband (s2 only)
source("R/series.R")   # series_stats (arrow/dplyr only)

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
  sources = lapply(names(paths), function(nm)
    src_status(paths[[nm]], prov_days[[nm]])) |> setNames(names(paths)))
jsonlite::write_json(status, file.path(out, "status.json"),
                     auto_unbox = TRUE, pretty = TRUE, na = "null")
message("status.json written")

## ---------------------------------------------------------------- series
## every region is a cell selection; add one by naming it here
region_cells <- list(
  cr = cells_latband(reg, -60, 60),
  global = NULL,
  nh = cells_latband(reg, 0, 90),
  sh = cells_latband(reg, -90, 0),
  tropics = cells_latband(reg, -23.4, 23.4),
  so60 = cells_latband(reg, -90, -60),
  no60 = cells_latband(reg, 60, 90),
  nino34 = reg$cell[reg$lat > -5 & reg$lat < 5 &
                    reg$lon > -170 & reg$lon < -120])
region_labels <- list(
  cr = "60S-60N", global = "Global",
  nh = "N hemisphere", sh = "S hemisphere",
  tropics = "Tropics 23S-23N", so60 = "South of 60S",
  no60 = "North of 60N",
  nino34 = "Nino 3.4")

rnd <- function(x) round(x, 3)
series <- lapply(paths, function(p) {
  g <- series_stats(p)
  out <- list(dates = iso(g$date))
  for (nm in names(region_cells)) {
    s <- if (is.null(region_cells[[nm]])) g
         else series_stats(p, region_cells[[nm]])
    out[[nm]] <- rnd(s$mean[match(g$date, s$date)])
  }
  out
})
jsonlite::write_json(list(regions = region_labels, sources = series),
                     file.path(out, "series.json"),
                     auto_unbox = TRUE, digits = NA, na = "null")
message(sprintf("series.json written (%i regions)", length(region_labels)))

## ---------------------------------------------- per-source cell exports
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
## Spilhaus rendering via PROJ (+proj=spilhaus needs PROJ >= 9.6);
## silently absent on older PROJ, seam-straddling cells culled
spil_of <- function(rings) tryCatch({
  s <- lapply(rings, function(r) {
    xy <- reproj::reproj_xy(r, "+proj=spilhaus", source = "EPSG:4326")
    if (!all(is.finite(xy))) return(NULL)
    seg <- sqrt(diff(xy[, 1])^2 + diff(xy[, 2])^2)
    if (max(seg) > 2e6) return(NULL)
    round(xy / 1000, 1)
  })
  ok <- !vapply(s, is.null, TRUE)
  if (!any(ok)) NULL else {
    message(sprintf("spilhaus: %i of %i cells (%i seam-culled)",
                    sum(ok), length(s), sum(!ok)))
    s
  }
}, error = function(e) { message("spilhaus unavailable: ", conditionMessage(e)); NULL })

## full years only; baseline is each source's own convention
cell_cfg <- list(oisst = list(years = 1982:2025, baseline = c(1982, 2011)),
                 ghrsst = list(years = 2003:2025, baseline = c(2003, 2022)))

for (src in names(paths)) {
  cfg <- cell_cfg[[src]]
  if (is.null(cfg)) next
  p <- paths[[src]]
  YEARS <- cfg$years
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
  b0 <- as.Date(sprintf("%i-01-01", cfg$baseline[1]))
  b1 <- as.Date(sprintf("%i-12-31", cfg$baseline[2]))
  base <- arrow::open_dataset(p) |>
    filter(date >= b0, date <= b1) |>
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

  rings <- lapply(percell$cell, ring_of)
  message(sprintf("[%s] %i cell rings built", src, length(rings)))
  spil <- spil_of(rings)

  cells_out <- lapply(seq_len(nrow(percell)), function(i) {
    o <- list(id = percell$cell[i], ring = rings[[i]],
         mean = round(percell$mean[i], 2), trend = round(percell$trend[i], 3),
         anom = round(percell$anom[i], 2), w = round(percell$w[i], 1),
         lon = round(percell$lon[i], 2), lat = round(percell$lat[i], 2))
    if (!is.null(spil) && !is.null(spil[[i]])) o$sring <- spil[[i]]
    o
  })

  mon <- arrow::open_dataset(p) |>
    filter(date >= d0) |>
    mutate(ym = lubridate::year(date) * 100L + lubridate::month(date)) |>
    group_by(cell, ym) |>
    summarise(sumw = sum(sumw), sumwx = sum(sumwx)) |>
    collect() |> mutate(m = sumwx / sumw)
  yms <- sort(unique(mon$ym))
  mat <- matrix(NaN, nrow(percell), length(yms))
  mat[cbind(match(mon$cell, percell$cell), match(mon$ym, yms))] <- mon$m
  con <- file(file.path(out, sprintf("monthly-%s.bin", src)), "wb")
  writeBin(as.numeric(t(mat)), con, size = 4, endian = "little")
  close(con)
  message(sprintf("monthly-%s.bin: %i cells x %i months", src, nrow(mat), length(yms)))

  region_sets <- Map(function(lab, cc) {
    ix <- if (is.null(cc)) seq_len(nrow(percell)) - 1L
          else which(percell$cell %in% cc) - 1L
    list(label = lab, cells = ix)
  }, region_labels, region_cells[names(region_labels)])

  jsonlite::write_json(
    list(source = src, years = range(YEARS),
         months = sprintf("%04i-%02i", yms %/% 100L, yms %% 100L),
         baseline = paste(cfg$baseline, collapse = "-"),
         regions = region_sets, cells = cells_out),
    file.path(out, sprintf("cells-%s.json", src)),
    auto_unbox = TRUE, digits = NA, na = "null")
  message(sprintf("cells-%s.json written", src))
}
