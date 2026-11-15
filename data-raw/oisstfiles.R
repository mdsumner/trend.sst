## data-raw/oisstfiles.R -- catalog of full-grid OISST dsns (no projwin:
## the whole grid is the product; +-60 is a query-time cell selection).
##
## Listed directly from NCEI's monthly directories, so the daily run sees
## a new file the day NOAA posts it (the aad-filelist release this used to
## read is refreshed weekly). Incremental: with an existing catalog only
## the last few months are re-listed (where _preliminary files become
## final); without one, all ~540 months are listed once.
## One file per date: the final file when both are listed.
## Never overwrites a good catalog with a shorter or failed listing.

base <- "https://www.ncei.noaa.gov/data/sea-surface-temperature-optimum-interpolation/v2.1/access/avhrr/"
vrtix <- "?a_srs=EPSG:4326&sd_name=sst&unscale=true&ot=Float32"
out <- "oisstfiles.parquet"
relist_months <- 3L

hrefs <- function(url) {
  html <- paste(readLines(url, warn = FALSE), collapse = "\n")
  m <- regmatches(html, gregexpr('href="[^"]+"', html))[[1]]
  gsub('^href="|"$', "", m)
}

months <- grep("^[0-9]{6}/?$", hrefs(base), value = TRUE)
months <- sub("/$", "", months)
stopifnot(length(months) > 500)

old <- if (file.exists(out)) arrow::read_parquet(out) else NULL
if (!is.null(old)) {
  keep_before <- format(seq(max(as.Date(old$date)), by = "-1 month",
                            length.out = relist_months)[relist_months], "%Y%m")
  todo <- months[months >= keep_before]
} else {
  todo <- months
}
message(sprintf("listing %i of %i NCEI months (%s..%s)", length(todo),
                length(months), todo[1], todo[length(todo)]))

files <- unlist(lapply(todo, function(m) {
  f <- grep("^oisst-avhrr-v02r01\\.[0-9]{8}(_preliminary)?\\.nc$",
            hrefs(paste0(base, m, "/")), value = TRUE)
  if (length(f)) paste0(base, m, "/", f) else character()
}))

new <- data.frame(url = files, stringsAsFactors = FALSE)
new$date <- as.POSIXct(as.Date(stringr::str_extract(basename(new$url), "[0-9]{8}"),
                               "%Y%m%d"), tz = "UTC")
new$preliminary <- grepl("_preliminary", new$url)
## final wins over preliminary for the same date
new <- new[order(new$date, new$preliminary), ]
new <- new[!duplicated(new$date), ]

new$dsn <- paste0("vrt:///vsicurl/", new$url, vrtix)
if (!is.null(old)) {
  ## rows before the re-listed months are kept as they were (dsn included)
  if (is.null(old$preliminary)) old$preliminary <- grepl("_preliminary", old$url)
  old <- old[as.Date(old$date) < min(as.Date(new$date)),
             c("date", "dsn", "url", "preliminary")]
  new <- rbind(as.data.frame(old), new[c("date", "dsn", "url", "preliminary")])
}
new <- new[order(new$date), c("date", "dsn", "url", "preliminary")]

stopifnot(!anyDuplicated(new$date), nrow(new) > 16000)
if (!is.null(old) && nrow(new) < nrow(old))
  stop(sprintf("new catalog (%i) shorter than the old (%i); keeping the old",
               nrow(new), nrow(old)))
gaps <- setdiff(seq(min(as.Date(new$date)), max(as.Date(new$date)), by = 1),
                as.Date(new$date))
if (length(gaps)) message(sprintf("note: %i missing dates, e.g. %s", length(gaps),
                                  format(as.Date(gaps[1], origin = "1970-01-01"))))
arrow::write_parquet(new, out)
message(sprintf("oisstfiles.parquet: %i dates, %s..%s, %i preliminary",
                nrow(new), format(min(as.Date(new$date))),
                format(max(as.Date(new$date))), sum(new$preliminary)))
