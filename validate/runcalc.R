
##docker run --rm -ti --security-opt seccomp=unconfined ghcr.io/mdsumner/gdal-builds:rocker-gdal-dev-python bash

calcfun <- function(dsn) {
  tres <- c(25000L, 25000L)
  ex <- c(-12775000, 12775000, -12700000, 12700000)

  opts <-c("-multi", "-wo", "NUM_THREADS=ALL_CPUS")
  crs <- "PROJCS[\"unknown\",GEOGCS[\"unknown\",DATUM[\"WGS_1984\",SPHEROID[\"WGS 84\",6378137,298.257223563,AUTHORITY[\"EPSG\",\"7030\"]],AUTHORITY[\"EPSG\",\"6326\"]],PRIMEM[\"Greenwich\",0,AUTHORITY[\"EPSG\",\"8901\"]],UNIT[\"degree\",0.0174532925199433,AUTHORITY[\"EPSG\",\"9122\"]]],PROJECTION[\"Lambert_Azimuthal_Equal_Area\"],PARAMETER[\"latitude_of_center\",0],PARAMETER[\"longitude_of_center\",0],PARAMETER[\"false_easting\",0],PARAMETER[\"false_northing\",0],UNIT[\"metre\",1,AUTHORITY[\"EPSG\",\"9001\"]],AXIS[\"Easting\",EAST],AXIS[\"Northing\",NORTH]]"
  mean(vapour::gdal_raster_data(dsn, target_res = tres, target_crs = crs, target_ext = ex, resample = "average", options = opts)[[1]], na.rm = TRUE)
}

library(arrow)
oisst <- read_parquet("https://github.com/mdsumner/trend.oisst/raw/main/oisstfiles.parquet")


library(vapour)
dsn <- oisst$dsn[15494]
system.time({
 print(calcfun(dsn))
})

## end vapour
## ---------------------------------------------------------------------------------------------


library(arrow)
oisst <- read_parquet("https://github.com/mdsumner/trend.oisst/raw/main/oisstfiles.parquet")
dsn <- oisst$dsn[15494]

library(terra)
tres <- c(25000L, 25000L)
ex <- c(-12775000, 12775000, -12700000, 12700000)
crs <- "PROJCS[\"unknown\",GEOGCS[\"unknown\",DATUM[\"WGS_1984\",SPHEROID[\"WGS 84\",6378137,298.257223563,AUTHORITY[\"EPSG\",\"7030\"]],AUTHORITY[\"EPSG\",\"6326\"]],PRIMEM[\"Greenwich\",0,AUTHORITY[\"EPSG\",\"8901\"]],UNIT[\"degree\",0.0174532925199433,AUTHORITY[\"EPSG\",\"9122\"]]],PROJECTION[\"Lambert_Azimuthal_Equal_Area\"],PARAMETER[\"latitude_of_center\",0],PARAMETER[\"longitude_of_center\",0],PARAMETER[\"false_easting\",0],PARAMETER[\"false_northing\",0],UNIT[\"metre\",1,AUTHORITY[\"EPSG\",\"9001\"]],AXIS[\"Easting\",EAST],AXIS[\"Northing\",NORTH]]"

target <- rast(ext(ex), res = tres, crs = crs)

#opts <-c("-multi", "-wo", "NUM_THREADS=ALL_CPUS")  ## can't use optoins in terra
system.time({
pp <- project(rast(dsn), target, by_util = TRUE, method = "average")
print(mean(values(pp, na.rm = TRUE, mat = FALSE)))
})
## end terra
## ---------------------------------------------------------------------------------------------


Sys.setenv("RETICULATE_PYTHON" = "/usr/bin/python3")
Sys.setenv("PYTHONPATH" = "$PYTHONPATH:/usr/local/lib/python3/dist-packages")

library(arrow)
oisst <- read_parquet("https://github.com/mdsumner/trend.oisst/raw/main/oisstfiles.parquet")
dsn <- oisst$dsn[15494]
tres <- c(25000L, 25000L)
ex <- c(-12775000, 12775000, -12700000, 12700000)
crs <- "PROJCS[\"unknown\",GEOGCS[\"unknown\",DATUM[\"WGS_1984\",SPHEROID[\"WGS 84\",6378137,298.257223563,AUTHORITY[\"EPSG\",\"7030\"]],AUTHORITY[\"EPSG\",\"6326\"]],PRIMEM[\"Greenwich\",0,AUTHORITY[\"EPSG\",\"8901\"]],UNIT[\"degree\",0.0174532925199433,AUTHORITY[\"EPSG\",\"9122\"]]],PROJECTION[\"Lambert_Azimuthal_Equal_Area\"],PARAMETER[\"latitude_of_center\",0],PARAMETER[\"longitude_of_center\",0],PARAMETER[\"false_easting\",0],PARAMETER[\"false_northing\",0],UNIT[\"metre\",1,AUTHORITY[\"EPSG\",\"9001\"]],AXIS[\"Easting\",EAST],AXIS[\"Northing\",NORTH]]"

library(reticulate)
gdal <- import("osgeo.gdal")
gdal$UseExceptions()
system.time({
ds <- gdal$Open(dsn)
opts <-c("-multi", "-wo", "NUM_THREADS=ALL_CPUS")
vrt <- gdal$Warp("", ds, xRes = tres[1L], yRes = tres[2L], outputBounds = ex[c(1, 3, 2, 4)], dstSRS = crs, format = "VRT", resampleAlg = "average", options = opts)
a <- vrt$ReadAsArray()
na_val <- ds$GetRasterBand(1L)$GetNoDataValue()
print(mean(a[a > na_val]))

})

## end osgeo.gdal
## ---------------------------------------------------------------------------------------------








