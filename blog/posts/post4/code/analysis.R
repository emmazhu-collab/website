# Run from post4: source("code/analysis.R"). Render calls the same script.
# Offline: reads fixed inputs and rebuilds every processed file, table, and figure.
library(tidyverse)
for (folder in c("data/processed", "results/tables", "results/figures")) {
  dir.create(folder, recursive = TRUE, showWarnings = FALSE)
}
start_date <- as.Date("2000-01-01")
data_files <- file.path("data/source", c("gasoline-monthly.csv", "natural-gas-monthly.csv", "cpi-monthly.csv"))
if (!all(file.exists(data_files))) stop("Missing source CSV. Restore the included inputs; see README.")

# Use the same saved inputs for every figure and number in the article.
gasoline <- read_csv(data_files[1], show_col_types = FALSE) |>
  arrange(date)
natural_gas <- read_csv(data_files[2], show_col_types = FALSE) |>
  arrange(date)
cpi <- read_csv(data_files[3], show_col_types = FALSE) |>
  arrange(date)

# Check the full monthly grid before matching, so lag() means the previous month.
expected_dates <- seq(start_date, as.Date("2026-08-01"), by = "month")
for (input in list(gasoline, natural_gas, cpi)) {
  stopifnot(identical(input$date, expected_dates), !anyDuplicated(input$date),
            all(input$value > 0, na.rm = TRUE))
}
stopifnot(!is.na(cpi$value[cpi$date == as.Date("2026-08-01")]),
          !is.na(cpi$value[cpi$date == start_date]),
          !is.na(gasoline$value[gasoline$date == start_date]),
          !is.na(natural_gas$value[natural_gas$date == start_date]))

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

# Adjacent-month percentage changes in real prices, not dollar differences.
# A missing observation also makes the next month's change unavailable.
changes <- monthly |>
  mutate(gasoline_change = 100 * (gasoline_real / lag(gasoline_real) - 1),
         natural_gas_change = 100 * (natural_gas_real / lag(natural_gas_real) - 1)) |>
  select(date, gasoline_change, natural_gas_change)
paired_changes <- changes |>
  filter(!is.na(gasoline_change), !is.na(natural_gas_change))
change_long <- paired_changes |>
  pivot_longer(-date, names_to = "fuel", values_to = "change") |>
  mutate(fuel = if_else(fuel == "gasoline_change", "Gasoline", "Natural gas"))
volatility <- change_long |>
  group_by(fuel) |>
  summarise(months = n(), average_absolute_change = mean(abs(change)),
            sd_change = sd(change), .groups = "drop")
movement <- paired_changes |>
  summarise(months = n(),
            same_direction_percent = 100 * mean(sign(gasoline_change) == sign(natural_gas_change)),
            correlation = cor(gasoline_change, natural_gas_change))
real_peaks <- monthly |>
  select(date, gasoline_real, natural_gas_real) |>
  pivot_longer(-date, names_to = "fuel", values_to = "real_price") |>
  group_by(fuel) |> filter(real_price == max(real_price, na.rm = TRUE)) |> ungroup()

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

write_csv(monthly, "data/processed/monthly-comparison.csv")
write_csv(summary, "results/tables/price-summary.csv")
write_csv(missing_months, "results/tables/missing-months.csv")
ggsave("results/figures/gasoline.png", plot1, width = 9, height = 5, dpi = 300)
ggsave("results/figures/natural-gas.png", plot2, width = 9, height = 5, dpi = 300)
ggsave("results/figures/real-price-comparison.png", plot3, width = 9, height = 5.5, dpi = 300)

plot4 <- ggplot(change_long, aes(x = fuel, y = change, fill = fuel)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey60") +
  geom_boxplot(width = 0.5, outlier.alpha = 0.5) +
  scale_fill_manual(values = c("Gasoline" = "#286789", "Natural gas" = "#B54F26")) +
  labs(title = "Natural gas had larger monthly price swings",
       subtitle = paste(nrow(paired_changes), "matched monthly changes in inflation-adjusted prices"),
       x = NULL, y = "Change from the previous month (%)",
       caption = "Source: EIA and BLS via FRED. Same months used for both fuels; no missing values filled.") +
  theme_minimal(base_size = 12) + theme(legend.position = "none")
write_csv(changes, "data/processed/monthly-changes.csv")
write_csv(volatility, "results/tables/volatility-summary.csv")
write_csv(movement, "results/tables/shared-movements.csv")
write_csv(real_peaks, "results/tables/real-price-peaks.csv")
ggsave("results/figures/monthly-swings.png", plot4, width = 9, height = 5, dpi = 180)
capture.output(sessionInfo(), file = "results/session-info.txt")
