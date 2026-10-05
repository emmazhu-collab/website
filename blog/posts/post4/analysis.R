# Run from the post4 folder. Rendering index.qmd also runs this script.
library(tidyverse)
library(fredr)

dir.create("data", showWarnings = FALSE)
dir.create("graph", showWarnings = FALSE)
dir.create("results", showWarnings = FALSE)

# Keep the saved data for the article. Set TRUE to download a fresh copy.
refresh_data <- FALSE
start_date <- as.Date("2000-01-01")
end_date <- as.Date("2026-08-31")
data_files <- c("data/gasoline-monthly.csv", "data/natural-gas-monthly.csv",
                "data/cpi-monthly.csv")

if (refresh_data || !all(file.exists(data_files))) {
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
  write_csv(tibble(downloaded_on = Sys.Date()), "data/download-date.csv")
}

# Use the same saved inputs for every figure and number in the article.
gasoline <- read_csv(data_files[1], show_col_types = FALSE) |>
  arrange(date)
natural_gas <- read_csv(data_files[2], show_col_types = FALSE) |>
  arrange(date)
cpi <- read_csv(data_files[3], show_col_types = FALSE) |>
  arrange(date)

# Match by month; retain missing values rather than filling them in.
monthly <- gasoline |>
  rename(gasoline = value) |>
  left_join(natural_gas |> rename(natural_gas = value), by = "date") |>
  left_join(cpi |> rename(cpi = value), by = "date") |>
  arrange(date)

# Convert prices to August 2026 dollars, then set January 2000 = 100.
monthly <- monthly |>
  mutate(
    gasoline_real = gasoline * cpi[date == as.Date("2026-08-01")] / cpi,
    natural_gas_real = natural_gas * cpi[date == as.Date("2026-08-01")] / cpi,
    gasoline_index = 100 * gasoline_real / gasoline_real[date == start_date],
    natural_gas_index = 100 * natural_gas_real / natural_gas_real[date == start_date]
  )

comparison <- monthly |>
  select(date, gasoline_index, natural_gas_index) |>
  pivot_longer(-date, names_to = "fuel", values_to = "price_index") |>
  mutate(fuel = if_else(fuel == "gasoline_index", "Gasoline", "Natural gas"))

# Summary values also supply the numbers in the article.
gasoline_peak <- gasoline |> filter(value == max(value, na.rm = TRUE))
gas_peak <- natural_gas |> filter(value == max(value, na.rm = TRUE))
last_month <- monthly |> filter(date == as.Date("2026-08-01"))
summary <- tibble(
  fuel = c("Gasoline", "Natural gas"),
  peak_month = c(gasoline_peak$date[1], gas_peak$date[1]),
  peak_nominal_price = c(gasoline_peak$value[1], gas_peak$value[1]),
  last_nominal_price = c(last_month$gasoline, last_month$natural_gas),
  last_real_index = c(last_month$gasoline_index, last_month$natural_gas_index)
)
missing_months <- monthly |> filter(is.na(gasoline) | is.na(natural_gas) | is.na(cpi))

plot1 <- ggplot(monthly, aes(x = date, y = gasoline)) +
  geom_line(linewidth = 0.6) +
  scale_x_date(breaks = seq(as.Date("2000-01-01"), as.Date("2025-01-01"), by = "5 years"),
               date_labels = "%Y") +
  scale_y_continuous(limits = c(0, 5.5)) +
  labs(
    title = "Gasoline's highest monthly price came in 2022",
    subtitle = "U.S. regular gasoline | January 2000-August 2026",
    x = NULL, y = "Dollars per gallon (not adjusted for inflation)",
    caption = "Source: EIA via FRED, GASREGW. Monthly averages; not seasonally adjusted."
  ) + theme_minimal(base_size = 12)

plot2 <- ggplot(monthly, aes(x = date, y = natural_gas)) +
  geom_line(linewidth = 0.6) +
  scale_x_date(breaks = seq(as.Date("2000-01-01"), as.Date("2025-01-01"), by = "5 years"),
               date_labels = "%Y") +
  scale_y_continuous(limits = c(0, 15)) +
  labs(
    title = "Natural gas reached its highest monthly price much earlier",
    subtitle = "Henry Hub spot price | January 2000-August 2026",
    x = NULL, y = "Dollars per million BTU (not adjusted for inflation)",
    caption = "Source: EIA via FRED, DHHNGSP. Monthly averages; missing months left blank."
  ) + theme_minimal(base_size = 12)

plot3 <- ggplot(comparison, aes(x = date, y = price_index, color = fuel)) +
  geom_hline(yintercept = 100, linetype = "dashed", color = "grey60") +
  geom_line(linewidth = 0.6) +
  scale_x_date(breaks = seq(as.Date("2000-01-01"), as.Date("2025-01-01"), by = "5 years"),
               date_labels = "%Y") +
  labs(
    title = "The two fuels did not follow the same path",
    subtitle = "Inflation-adjusted prices | January 2000 = 100",
    x = NULL, y = "Real price index", color = NULL,
    caption = "Source: EIA and BLS via FRED. CPI-U adjustment; missing months left blank."
  ) + theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")

write_csv(monthly, "results/monthly-comparison.csv")
write_csv(summary, "results/price-summary.csv")
write_csv(missing_months, "results/missing-months.csv")
ggsave("graph/gasoline.png", plot1, width = 9, height = 5, dpi = 300)
ggsave("graph/natural-gas.png", plot2, width = 9, height = 5, dpi = 300)
ggsave("graph/real-price-comparison.png", plot3, width = 9, height = 5.5, dpi = 300)
