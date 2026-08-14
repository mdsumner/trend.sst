## Pacific mean SST climatology-style plot:
## one line per year over day-of-year, shaded light->dark by year,
## with the current year drawn on top in colour.

library(ggplot2)

d <- read.csv("ghrsst_pacific_sst.csv")
d$date <- as.Date(d$date)
d$year <- as.integer(format(d$date, "%Y"))
d$doy  <- as.integer(format(d$date, "%j"))

## if the values are Kelvin, make them Celsius
if (mean(d$pacific_mean, na.rm = TRUE) > 100) {
  d$pacific_mean <- d$pacific_mean - 273.15
}

this_year <- as.integer(format(Sys.Date(), "%Y"))
past    <- d[d$year <  this_year, ]
current <- d[d$year == this_year, ]

ggplot() +
  geom_line(data = past,
            aes(doy, pacific_mean, group = year, colour = year),
            linewidth = 0.4) +
  scale_colour_gradient(low = "grey85", high = "grey25", name = "Year",
                        breaks = pretty(range(past$year), 4)) +
  geom_line(data = current,
            aes(doy, pacific_mean),
            colour = "firebrick", linewidth = 1) +
  annotate("text",
           x = max(current$doy), y = current$pacific_mean[which.max(current$doy)],
           label = this_year, colour = "firebrick",
           hjust = -0.2, fontface = "bold") +
  scale_x_continuous(breaks = c(1, 91, 182, 274, 366),
                     labels = c("Jan", "Apr", "Jul", "Oct", "Jan"),
                     expand = expansion(mult = c(0.01, 0.05))) +
  labs(x = NULL, y = "Pacific mean SST (C)",
       title = "GHRSST Pacific mean SST by day of year",
       subtitle = sprintf("Grey lines: %i-%i, red: %i",
                          min(past$year), max(past$year), this_year)) +
  theme_minimal()

ggsave("ghrsst_pacific_doy.png", width = 10, height = 6, dpi = 150)

## bonus: per-doy climatology table if you want stats rather than the plot
clim <- aggregate(pacific_mean ~ doy, data = past,
                  FUN = function(x) c(mean = mean(x), min = min(x), max = max(x)))
clim <- do.call(data.frame, clim)
names(clim) <- c("doy", "clim_mean", "clim_min", "clim_max")
head(clim)
