## data-raw/oisstfiles.R -- catalog of full-grid OISST dsns (no projwin:
## the whole grid is the product; +-60 is a query-time cell selection).

oisst <- arrow::read_parquet("https://github.com/mdsumner/aad-filelist/releases/download/latest/noaa_oisst_daily.parquet")
vrtix <- "?a_srs=EPSG:4326&sd_name=sst&unscale=true&ot=Float32"
url <- gsub("/rdsi/PUBLIC/raad/data/", "https://", oisst$url)
oisst$dsn <- paste0("vrt:///vsicurl/", url, vrtix)
oisst$date <- as.POSIXct(as.Date(stringr::str_extract(basename(url), "[0-9]{8}"), "%Y%m%d"), tz = "UTC")
oisst$was_downloaded <- NULL
oisst$ok <- NULL
oisst$sync_time <- NULL
arrow::write_parquet(oisst, "oisstfiles.parquet")
