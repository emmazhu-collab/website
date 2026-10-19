# Run from this post folder, or use source("analysis.R", chdir = TRUE).
# Rendering index.qmd also runs this script.
dir.create("graph", showWarnings = FALSE)
dir.create("results", showWarnings = FALSE)

library(tidyverse)
library(ipumsr)

ddi <- read_ipums_ddi("data/cps_00001.xml")
cps <- read_ipums_micro(ddi, data_file = "data/cps_00001.dat.gz")
cps |> count(YEAR, MONTH)

adults <- cps |>
  filter(
    YEAR >= 2020, YEAR <= 2026, MONTH == 1,
    AGE >= 25, AGE <= 64, WTFINL > 0,
    EMPSTAT %in% c(10, 12, 20, 21, 22, 30:36)
  ) |>
  mutate(
    education = case_when(
      EDUC %in% c(2, 10, 20, 30, 40, 50, 60, 71) ~ "Less than high school",
      EDUC == 73 ~ "High school",
      EDUC %in% c(81, 91, 92) ~ "Some college / associate",
      EDUC %in% c(111, 123, 124, 125) ~ "Bachelor's or higher"
    ),
    unemployed = EMPSTAT %in% c(20, 21, 22),
    labor_status = case_when(
      EMPSTAT %in% c(10, 12) ~ "Employed",
      EMPSTAT %in% c(20, 21, 22) ~ "Unemployed",
      EMPSTAT %in% 30:36 ~ "Not in labor force"
    ),
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

# Unemployment rates use the labor force, not all adults.
workers <- adults |> filter(labor_status != "Not in labor force")

rates <- workers |>
  group_by(YEAR, education) |>
  summarise(
    sample_n = n(),
    rate = 100 * weighted.mean(unemployed, WTFINL),
    .groups = "drop"
  )

latest <- rates |> filter(YEAR == 2026)

# A new margin: status shares among ALL civilian adults ages 25-64.
# This denominator differs from the labor-force denominator in rates.
status_shares <- adults |>
  filter(YEAR == 2026) |>
  group_by(education, labor_status) |>
  summarise(sample_n = n(), weighted_people = sum(WTFINL), .groups = "drop") |>
  group_by(education) |>
  mutate(share = 100 * weighted_people / sum(weighted_people)) |>
  ungroup() |>
  mutate(labor_status = factor(labor_status,
    levels = c("Employed", "Unemployed", "Not in labor force")))
stopifnot(all(abs((status_shares |> group_by(education) |>
  summarise(total = sum(share)))$total - 100) < 1e-8))

plot1 <- ggplot(status_shares, aes(x = education, y = share, fill = labor_status)) +
  geom_col(width = 0.65, position = position_stack(reverse = TRUE)) +
  geom_text(aes(label = paste0(round(share, 1), "%")),
            position = position_stack(vjust = 0.5, reverse = TRUE), size = 3.5) +
  coord_flip() +
  scale_y_continuous(limits = c(0, 100), breaks = seq(0, 100, 25),
                     labels = function(x) paste0(x, "%"), expand = expansion(mult = c(0, 0.02))) +
  scale_fill_manual(values = c("Employed" = "#9ecae1", "Unemployed" = "#fdae6b",
                               "Not in labor force" = "#d9d9d9")) +
  labs(title = "Unemployment does not count everyone without a job",
       subtitle = "January 2026 | All civilian adults ages 25-64 in each education group",
       x = NULL, y = "Share of each education group (%)", fill = NULL,
       caption = "Source: IPUMS CPS, weighted using WTFINL. Orange is a share of all adults, not the unemployment rate.") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom", panel.grid.major.y = element_blank())

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
    title = "The education gap remains within each age group",
    subtitle = "January 2026 | Civilian labor force",
    x = "Unemployment rate (%)", y = NULL,
    caption = "Source: IPUMS CPS. Weighted using WTFINL. Same scale in all panels."
  ) +
  theme_minimal(base_size = 12)

# Save the summaries and figures used in this post.
dir.create("results", showWarnings = FALSE)
write_csv(rates, "results/rates-by-year.csv")
write_csv(age_rates, "results/rates-by-age.csv")
write_csv(status_shares, "results/status-by-education.csv")
ggsave("graph/education-labor-status.png", plot1, width = 11, height = 5.5, dpi = 300)
ggsave("graph/education-trend.png", plot2, width = 9, height = 5.5, dpi = 300)
ggsave("graph/education-by-age.png", plot3, width = 9, height = 6.5, dpi = 300)
