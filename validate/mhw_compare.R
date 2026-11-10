## Marine heatwaves, step 6: a region's pixel MHWs (MUR, 2003-2025
## baseline) vs its box-mean series, with OISST (1982-2011) as the
## paired classic reference.
##
## Rscript validate/mhw_compare.R <region>  -> prints checks + one figure
##   per focus window: cache/mhw/<region>/mhw_<region>_<window>.png

suppressMessages(devtools::load_all(quiet = TRUE))
library(heatwaveR)
args <- commandArgs(trailingOnly = TRUE)
region <- mhw_region(if (length(args)) args[1] else "tasman")
root <- region$root
px <- read.csv(file.path(root, "pixel_daily.csv")); px$date <- as.Date(px$date)
bx <- read.csv(file.path(root, "boxmean.csv")); bx$date <- as.Date(bx$date)
maps <- readRDS(file.path(root, "pixel_maps.rds"))
stopifnot(identical(px$date, bx$date))
baseline <- c("2003-01-01", "2025-12-31")

hw <- function(t, temp, bl) {
  clm <- ts2clm(data.frame(t = t, temp = temp), climatologyPeriod = bl)
  list(clm = clm, ev = detect_event(clm, protoEvents = TRUE),
       events = detect_event(clm)$event)
}
box <- hw(bx$date, bx$mean, baseline)

## 1. linearity check: area-mean of pixel anomalies == box-mean anomaly
##    (seas is linear in the data; differences only from 4-dp rounding)
d_anom <- px$sumw_anom / px$sumw - (box$clm$temp - box$clm$seas)
cat(sprintf("1. area-mean pixel anom vs box anom: max |diff| %.2g C\n", max(abs(d_anom))))

## 2. area fraction in MHW
px$frac <- px$sumw_mhw / px$sumw
px$box_event <- box$ev$event
cat(sprintf("2. whole record: mean area fraction in MHW %.3f; box-mean MHW day fraction %.3f\n",
            mean(px$frac), mean(px$box_event)))
cat(sprintf("   area fraction on box-mean MHW days %.2f vs other days %.2f\n",
            mean(px$frac[px$box_event]), mean(px$frac[!px$box_event])))

## 3. per focus window: area in MHW, and per-pixel stats
s5 <- function(m) round(stats::quantile(m, c(0, .1, .5, .9, 1), na.rm = TRUE), 2)
for (nm in names(region$windows)) {
  win <- region$windows[[nm]]; ws <- as.Date(win$stats)
  w <- px$date >= ws[1] & px$date <= ws[2]
  pk <- which(w)[which.max(px$frac[w])]
  cat(sprintf("3. %s, %s..%s (%i days of data):\n", win$label, ws[1],
              format(min(ws[2], max(px$date))), sum(w)))
  cat(sprintf("   area in MHW: mean %.2f, peak %.2f on %s (cat III+IV %.3f); days >= 50%% area %i; box-mean MHW days %i\n",
              mean(px$frac[w]), px$frac[pk], format(px$date[pk]),
              (px$sumw_cat3[pk] + px$sumw_cat4[pk]) / px$sumw[pk],
              sum(px$frac[w] >= 0.5), sum(px$box_event[w])))
  cat("   per-pixel quantiles 0/10/50/90/100%:\n")
  cat("     MHW days:      ", s5(maps[[paste0(nm, "_days")]]), "\n")
  cat("     longest event: ", s5(maps[[paste0(nm, "_longest")]]), "\n")
  cat("     max anom (C):  ", s5(maps[[paste0(nm, "_max_anom")]]), "\n")
  cat("     max category 0..4:", tabulate(maps[[paste0(nm, "_max_cat")]] + 1L, 5L), "\n")
}
cat(sprintf("4. last day %s: area in MHW %.2f\n", format(max(px$date)), tail(px$frac, 1)))

## 5. annual: mean pixel MHW days vs box-mean MHW days
ad <- apply(maps$annual_days, 3, mean, na.rm = TRUE)
yb <- tapply(px$box_event, format(px$date, "%Y"), sum)
cat("5. annual MHW days, mean pixel vs box-mean:\n")
print(round(rbind(pixel_mean = ad, box_mean = yb[names(ad)]), 0))

## OISST classic reference on the S2 cells with centres in the box
reg <- arrow::read_parquet("s2_registry.parquet")
b <- region$bbox
cin <- reg$cell[reg$lon >= b[["xmin"]] & reg$lon < b[["xmax"]] &
                reg$lat >= b[["ymin"]] & reg$lat < b[["ymax"]]]
so <- series_stats("sums/oisst", cin)
oi <- hw(as.Date(so$date), so$mean, c("1982-01-01", "2011-12-31"))

## ---- figure --------------------------------------------------------------
ink <- "#0b0b0b"; ink2 <- "#52514e"; muted <- "#898781"; grid <- "#e1e0d9"
surface <- "#fcfcfb"; land <- "#e1e0d9"
cat_col <- c("#86b6ef", "#3987e5", "#1c5cab", "#0d366b")   # ordinal blue 250/400/550/700
ref_col <- c(mur = "#eb6834", oisst = "#1baf7a")          # categorical slots 2, 3
seq_ramp <- grDevices::colorRampPalette(c("#cde2fb", "#9ec5f4", "#6da7ec",
                                          "#3987e5", "#256abf", "#184f95", "#0d366b"))

spans <- function(ev, x0, x1) {
  e <- ev[ev$date_end >= x0 & ev$date_start <= x1, ]
  data.frame(s = pmax(as.Date(e$date_start), x0), e = pmin(as.Date(e$date_end), x1))
}
## one colour scale for every map so windows are comparable
zmax_all <- ceiling(max(unlist(maps[paste0(names(region$windows), "_days")]),
                        na.rm = TRUE) / 50) * 50
box_lab <- sprintf("%g–%g°E, %g–%g°S", region$lon0, max(region$lon) + 0.01,
                   -region$lat0, -min(region$lat) + 0.01)

plot_window <- function(x0, x1, map_key, title, map_title, file, tick_by) {
  pw <- px[px$date >= x0 & px$date <= x1, ]
  sp_mur <- spans(box$events, x0, x1); sp_oi <- spans(oi$events, x0, x1)
  oi_end <- max(as.Date(so$date))

  png(file, width = 2000, height = 1500, res = 200, bg = surface)
  on.exit(dev.off())
  layout(matrix(c(1, 2, 3, 3), 2), widths = c(1.35, 1), heights = c(1, 0.32))
  par(family = "sans", col.axis = muted, col.lab = ink2, fg = muted, las = 1,
      mgp = c(2.2, 0.5, 0), tcl = -0.25, cex.axis = 0.85)

  ## A: stacked area by category
  par(mar = c(1.2, 5.6, 3.6, 1))
  cum <- t(apply(as.matrix(pw[, paste0("sumw_cat", 1:4)]) / pw$sumw, 1, cumsum))
  plot(c(x0, x1), c(0, 1), type = "n", xaxs = "i", yaxs = "i", axes = FALSE,
       xlab = "", ylab = "Ocean area in MHW")
  abline(h = seq(0.25, 0.75, 0.25), col = grid, lwd = 0.8)
  lo <- rep(0, nrow(pw))
  for (k in 1:4) {
    polygon(c(pw$date, rev(pw$date)), c(cum[, k], rev(lo)), col = cat_col[k], border = NA)
    lo <- cum[, k]
  }
  axis(2, at = seq(0, 1, 0.25), labels = paste0(seq(0, 100, 25), "%"), lwd = 0, lwd.ticks = 0)
  abline(h = 0, col = "#c3c2b7", lwd = 1)
  if (max(pw$date) < x1) {
    text(max(pw$date), cum[nrow(cum), 4], sprintf(" %s\n %d%%", format(max(pw$date), "%d %b"),
         round(100 * cum[nrow(cum), 4])), adj = c(0, 0.5), cex = 0.7, col = ink2, xpd = NA)
  }
  mtext(title, side = 3, line = 2.1, adj = 0, col = ink, font = 2, cex = 0.95)
  mtext(paste0("MUR 0.01°, per-pixel Hobday (2016) events, baseline 2003–2025; ", box_lab),
        side = 3, line = 1.0, adj = 0, col = ink2, cex = 0.72)
  legend("topright", inset = c(0, -0.02), legend = c("I Moderate", "II Strong", "III Severe", "IV Extreme"),
         fill = cat_col, border = NA, bty = "n", horiz = TRUE, cex = 0.72,
         text.col = ink2, x.intersp = 0.5)

  ## B: box-mean event spans (OISST: grey hatch where the local sums end)
  par(mar = c(3, 5.6, 0.4, 1))
  plot(c(x0, x1), c(0.4, 2.6), type = "n", xaxs = "i", axes = FALSE, xlab = "", ylab = "")
  if (nrow(sp_mur)) rect(sp_mur$s, 1.65, sp_mur$e + 1, 2.35, col = ref_col["mur"], border = surface, lwd = 2)
  if (nrow(sp_oi)) rect(sp_oi$s, 0.65, sp_oi$e + 1, 1.35, col = ref_col["oisst"], border = surface, lwd = 2)
  if (oi_end < x1) {
    rect(oi_end + 1, 0.65, x1 + 1, 1.35, col = grid, border = NA)
    rect(oi_end + 1, 0.65, x1 + 1, 1.35, density = 12, angle = 45, col = muted, border = NA, lwd = 0.6)
    lab <- sprintf("no local OISST after %s", format(oi_end, "%d %b"))
    lw <- strwidth(lab, cex = 0.68); lh <- strheight(lab, cex = 0.68)
    rect(oi_end + 4 - 2, 1 - lh, oi_end + 4 + lw + 2, 1 + lh, col = surface, border = NA)
    text(oi_end + 4, 1, lab, adj = c(0, 0.5), cex = 0.68, col = ink2)
  }
  axis(2, at = c(2, 1), labels = c("MUR box mean\nbase 2003–2025", "OISST cells\nbase 1982–2011"),
       lwd = 0, cex.axis = 0.7, col.axis = ink2)
  ticks <- seq(x0, x1 + 1, by = tick_by)
  axis(1, at = ticks, labels = format(ticks, "%b %Y"), lwd = 0, lwd.ticks = 0.8, col.ticks = muted)

  ## C: map of MHW days per pixel
  par(mar = c(3, 3.2, 3.6, 4.6))
  z <- maps[[map_key]]
  brks <- seq(0, zmax_all, length.out = 15)
  plot(range(maps$lon), range(maps$lat), type = "n", asp = 1 / cos(mean(maps$lat) * pi / 180),
       xaxs = "i", yaxs = "i", axes = FALSE, xlab = "", ylab = "")
  ## land only inside the data window (the plot region beyond it is not land)
  rect(min(maps$lon) - 0.005, min(maps$lat) - 0.005, max(maps$lon) + 0.005,
       max(maps$lat) + 0.005, col = land, border = NA)
  image(maps$lon, rev(maps$lat), z[, ncol(z):1], breaks = brks, col = seq_ramp(14),
        add = TRUE, useRaster = TRUE)
  axis(1, at = seq(148, 156, 2), labels = paste0(seq(148, 156, 2), "°E"), lwd = 0, lwd.ticks = 0.8)
  axis(2, at = seq(-44, -38, 2), labels = paste0(abs(seq(-44, -38, 2)), "°S"), lwd = 0, lwd.ticks = 0.8)
  mtext(map_title, side = 3, line = 2.1, adj = 0, col = ink, font = 2, cex = 0.95)
  mtext(sprintf("median %d days; land grey; scale shared across figures",
                round(median(z, na.rm = TRUE))),
        side = 3, line = 1.0, adj = 0, col = ink2, cex = 0.72)
  usr <- par("usr"); bx0 <- usr[2] + 0.04 * diff(usr[1:2]); bx1 <- bx0 + 0.035 * diff(usr[1:2])
  yy <- seq(min(maps$lat), max(maps$lat), length.out = 15)
  rect(bx0, yy[-15], bx1, yy[-1], col = seq_ramp(14), border = NA, xpd = NA)
  lab_at <- pretty(c(0, zmax_all), 4); lab_at <- lab_at[lab_at <= zmax_all]
  text(bx1, min(yy) + lab_at / zmax_all * diff(range(yy)), lab_at, pos = 4, cex = 0.7,
       col = muted, xpd = NA)
  cat("figure:", file, "\n")
}

last <- max(px$date)
for (nm in names(region$windows)) {
  win <- region$windows[[nm]]; wp <- as.Date(win$plot)
  partial <- last < as.Date(win$stats[2])
  map_label <- if (is.null(win$map_label)) {
    sprintf("%s–%s", format(as.Date(win$stats[1]), "%d %b"), format(min(last, as.Date(win$stats[2])), "%d %b %Y"))
  } else win$map_label
  plot_window(wp[1], wp[2], paste0(nm, "_days"),
              sprintf("%s %s%s: share of box in marine heatwave", region$title, win$label,
                      if (partial) sprintf(" (to %s)", format(last, "%d %b")) else ""),
              paste("MHW days per pixel,", map_label),
              file.path(root, sprintf("mhw_%s_%s.png", region$name, nm)), "2 months")
}
