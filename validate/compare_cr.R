## validate/compare_cr.R -- the exactness side-illustration.
## Three series for 60S-60N:
##   A. cell-based (center-in-band selection)      <- the product
##   B. cell-based brackets (straddling ring in / out)
##   C. pixel-exact clip via projwin dsns          <- the old oracle
## Expect: C inside the B bracket, A - C small (0.01-0.05 C), stationary,
## with a seasonal wiggle. One figure, argument settled.

devtools::load_all()

reg <- arrow::read_parquet("s2_registry.parquet")
sums <- file.path("sums", "oisst")

## A and B: three nested cell selections; half-height ~1.3 deg puts the
## straddling ring between the inner and outer sets
inner <- cells_latband(reg, -60 + 1.3, 60 - 1.3)
center <- cells_latband(reg, -60, 60)
outer <- cells_latband(reg, -60 - 1.3, 60 + 1.3)
sA <- series_stats(sums, center)
sBin <- series_stats(sums, inner)
sBout <- series_stats(sums, outer)

## C: pixel-exact, the original three-way-validated warp trick, on the
## projwin'd dsns (sample of dates is enough; full series if patient)
src <- oisst_source("oisstfiles.parquet")
clip <- "&projwin=0,60,360,-60"
calcfun <- function(dsn) {
  tres <- c(25000, 25000)
  ex <- c(-12775000, 12775000, -12700000, 12700000)
  crs <- "+proj=laea +lon_0=0 +lat_0=0"
  mean(vapour::gdal_raster_data(paste0(dsn, clip), target_res = tres,
       target_crs = crs, target_ext = ex,
       resample = "average")[[1]], na.rm = TRUE)
}
sample_i <- round(seq(1, nrow(src$files), length.out = 200))
sC <- data.frame(date = src$files$date[sample_i],
                 exact = vapply(src$files$dsn[sample_i], calcfun, 0.0))

m <- merge(sA[c("date", "mean")], sC, by = "date")
m$diff <- m$mean - m$exact
summary(m$diff)

op <- par(mfrow = c(3, 1), mar = c(3, 4, 1, 1))
plot(sA$date, sA$mean, type = "l", ylab = "60S-60N mean SST")
lines(sC$date, sC$exact, col = "firebrick")
plot(m$date, m$diff, type = "l", ylab = "cell - exact")
plot(as.integer(format(m$date, "%j")), m$diff, ylab = "diff by doy")
par(op)
