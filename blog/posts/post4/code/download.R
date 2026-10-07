# Optional: request three series once. Run from post4.
# Saved article inputs are never replaced automatically.
library(tidyverse)
library(fredr)
start_date <- as.Date("2000-01-01")
end_date <- as.Date("2026-08-31")
download_folder <- file.path("data", "downloads", as.character(Sys.Date()))
dir.create(download_folder, recursive = TRUE, showWarnings = FALSE)
data_files <- file.path(download_folder, c("gasoline-monthly.csv", "natural-gas-monthly.csv", "cpi-monthly.csv"))
if (Sys.getenv("FRED_API_KEY") == "") {
  stop("Set FRED_API_KEY before downloading, or use the saved data files.")
}
fredr_set_key(Sys.getenv("FRED_API_KEY"))

# FRED converts the weekly and daily prices to monthly averages.
gasoline <- fredr(
  series_id = "GASREGW",
  observation_start = start_date, observation_end = end_date,
  frequency = "m", aggregation_method = "avg"
) |> select(date, value)

natural_gas <- fredr(
  series_id = "DHHNGSP",
  observation_start = start_date, observation_end = end_date,
  frequency = "m", aggregation_method = "avg"
) |> select(date, value)

cpi <- fredr(
  series_id = "CPIAUCNS",
  observation_start = start_date, observation_end = end_date
) |> select(date, value)

write_csv(gasoline, data_files[1])
write_csv(natural_gas, data_files[2])
write_csv(cpi, data_files[3])
write_csv(tibble(downloaded_on = Sys.Date()), file.path(download_folder, "download-date.csv"))
message("Downloaded to ", download_folder, ". Review before replacing data/source inputs.")
