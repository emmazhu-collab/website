# Run from this post folder, or use source("analysis.R", chdir = TRUE).
# Rendering index.qmd also runs this script.
dir.create("graph", showWarnings = FALSE)
dir.create("results", showWarnings = FALSE)

library(tidyverse)
library(ipumsr)

ddi <- read_ipums_ddi("data/cps_00001.xml")
cps <- read_ipums_micro(ddi, data_file = "data/cps_00001.dat.gz")
cps |> count(YEAR, MONTH)

workers <- cps |>
  filter(
    YEAR >= 2020, YEAR <= 2026, MONTH == 1,
    AGE >= 25, AGE <= 64, WTFINL > 0,
    EMPSTAT %in% c(10, 12, 20, 21, 22)
  ) |>
  mutate(
    education = case_when(
      EDUC %in% c(2, 10, 20, 30, 40, 50, 60, 71) ~ "Less than high school",
      EDUC == 73 ~ "High school",
      EDUC %in% c(81, 91, 92) ~ "Some college / associate",
      EDUC %in% c(111, 123, 124, 125) ~ "Bachelor's or higher"
    ),
    unemployed = EMPSTAT %in% c(20, 21, 22),
    age_group = case_when(
      AGE < 35 ~ "25-34",
      AGE < 45 ~ "35-44",
      AGE < 55 ~ "45-54",
      TRUE ~ "55-64"
    )
  ) |>
  filter(!is.na(education)) |>
  mutate(
    education = factor(education, levels = c(
      "Less than high school", "High school",
      "Some college / associate", "Bachelor's or higher"
    ))
  )

rates <- workers |>
  group_by(YEAR, education) |>
  summarise(
    sample_n = n(),
    rate = 100 * weighted.mean(unemployed, WTFINL),
    .groups = "drop"
  )

latest <- rates |> filter(YEAR == 2026)

plot1 <- ggplot(latest, aes(x = rate, y = education)) +
  geom_point(size = 3) +
  scale_x_continuous(limits = c(0, 9), breaks = seq(0, 9, 3)) +
  labs(
    title = "Unemployment is lower among more educated workers",
    subtitle = "January 2026 | Civilian labor force, ages 25-64",
    x = "Unemployment rate (%)", y = NULL,
    caption = "Source: IPUMS CPS. Weighted using WTFINL."
  ) +
  theme_minimal(base_size = 12)

plot2 <- ggplot(rates, aes(x = YEAR, y = rate, color = education)) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 2) +
  scale_x_continuous(breaks = 2020:2026) +
  scale_y_continuous(limits = c(0, 12), breaks = seq(0, 12, 3)) +
  labs(
    title = "The education gap appears in every January sample",
    subtitle = "Civilian labor force, ages 25-64",
    x = NULL, y = "Unemployment rate (%)", color = "Education",
    caption = "Source: IPUMS CPS. Weighted using WTFINL. January only."
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")

age_rates <- workers |>
  filter(YEAR == 2026) |>
  group_by(age_group, education) |>
  summarise(
    sample_n = n(),
    rate = 100 * weighted.mean(unemployed, WTFINL),
    .groups = "drop"
  )

plot3 <- ggplot(age_rates, aes(x = rate, y = education)) +
  geom_point(size = 3) +
  facet_wrap(~ age_group, ncol = 2) +
  scale_x_continuous(limits = c(0, 13), breaks = c(0, 4, 8, 12)) +
  labs(
    title = "The education gap is largest among ages 25-34",
    subtitle = "January 2026 | Civilian labor force",
    x = "Unemployment rate (%)", y = NULL,
    caption = "Source: IPUMS CPS. Weighted using WTFINL. Same scale in all panels."
  ) +
  theme_minimal(base_size = 12)

# Save the summaries and figures used in this post.
dir.create("results", showWarnings = FALSE)
write_csv(rates, "results/rates-by-year.csv")
write_csv(age_rates, "results/rates-by-age.csv")
ggsave("graph/education-2026.png", plot1, width = 9, height = 5.5, dpi = 300)
ggsave("graph/education-trend.png", plot2, width = 9, height = 5.5, dpi = 300)
ggsave("graph/education-by-age.png", plot3, width = 9, height = 6.5, dpi = 300)
