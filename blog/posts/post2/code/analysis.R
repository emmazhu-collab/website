# Run from post2: source("code/analysis.R"). The article calls this too.
# Input CSVs are preserved; every processed file, table, and figure is rebuilt.
library(tidyverse)
for (folder in c("data/processed", "results/tables", "results/figures")) {
  dir.create(folder, recursive = TRUE, showWarnings = FALSE)
}

# This is the previous scrape's saved cleaned CSV, not a raw HTML archive.
restaurants_raw <- read_csv("data/source/restaurant-options-saved.csv", show_col_types = FALSE)
restaurants <- restaurants_raw |>
  mutate(restaurant = str_squish(restaurant), meal = str_squish(meal),
         price = str_squish(price)) |>
  filter(!is.na(restaurant), restaurant != "")

duplicates <- restaurants |> count(meal, price, url) |> filter(n > 1)
stopifnot(nrow(duplicates) == 0, !anyNA(restaurants),
          all(restaurants$meal %in% c("LUNCH", "DINNER")),
          all(restaurants$price %in% c("$20", "$30", "$40")))
choices <- restaurants |> count(meal, price, sort = TRUE)

# These seven broad cuisine labels were added by reading the linked menus.
# They are examples, not a classification of every event participant.
notes <- read_csv("data/source/cuisine-notes.csv", show_col_types = FALSE)
additions <- read_csv("data/source/menu-additions.csv", show_col_types = FALSE)
stopifnot(!anyDuplicated(notes$url), !anyNA(notes), !anyNA(additions))
stopifnot(all(notes$url %in% restaurants$url), all(additions$url %in% notes$url))

# Add only the three options documented on the detail menus.
# Keep the original main-page CSV unchanged so differences remain visible.
reviewed <- bind_rows(restaurants, additions |> select(restaurant, meal, price, url)) |>
  inner_join(notes, by = "url") |>
  mutate(price_dollars = parse_number(price))
stopifnot(!anyDuplicated(reviewed[c("meal", "price", "url")]),
          !anyNA(reviewed), all(reviewed$price_dollars %in% c(20, 30, 40)),
          all(reviewed$meal %in% c("LUNCH", "DINNER")))

# Count a restaurant once per meal using its cheapest listed menu.
# A second menu at the same place does not create a second restaurant.
minimum_prices <- reviewed |>
  group_by(restaurant, url, cuisine, meal) |>
  summarise(minimum_price = min(price_dollars), .groups = "drop")

budget_choices <- tibble()
for (budget in c(20, 30, 40)) {
  this_budget <- minimum_prices |>
    filter(minimum_price <= budget) |>
    count(cuisine, meal) |>
    mutate(budget = budget)
  budget_choices <- bind_rows(budget_choices, this_budget)
}
# Keep zero counts explicit if the input changes.
budget_choices <- budget_choices |>
  complete(cuisine = notes$cuisine, meal = c("LUNCH", "DINNER"),
           budget = c(20, 30, 40), fill = list(n = 0)) |>
  arrange(cuisine, meal, budget)

# How many extra restaurants does the next $10 make affordable?
budget_changes <- budget_choices |>
  group_by(cuisine, meal) |>
  arrange(budget, .by_group = TRUE) |>
  mutate(extra_restaurants = n - lag(n)) |>
  ungroup()

# Compare lunch and dinner counts at the same budget.
meal_comparison <- budget_choices |>
  select(cuisine, meal, budget, n) |>
  pivot_wider(names_from = meal, values_from = n) |>
  mutate(extra_at_lunch = LUNCH - DINNER)

# Direct menu-price comparison for restaurants offering both meals.
meal_prices <- minimum_prices |>
  select(restaurant, cuisine, meal, minimum_price) |>
  pivot_wider(names_from = meal, values_from = minimum_price) |>
  filter(!is.na(LUNCH), !is.na(DINNER)) |>
  mutate(dinner_minus_lunch = DINNER - LUNCH)

stopifnot(all(budget_changes$extra_restaurants >= 0, na.rm = TRUE))

budget_plot <- budget_choices |>
  mutate(meal = if_else(meal == "LUNCH", "Lunch", "Dinner")) |>
  ggplot(aes(x = factor(budget), y = n, fill = meal)) +
  geom_col(position = "dodge", width = 0.7) +
  facet_wrap(~ cuisine, nrow = 1) +
  scale_x_discrete(labels = c("20" = "$20", "30" = "$30", "40" = "$40")) +
  scale_y_continuous(breaks = 0:max(budget_choices$n)) +
  scale_fill_manual(values = c("Dinner" = "#B54F26", "Lunch" = "#286789")) +
  labs(title = "A larger budget adds different choices for each cuisine",
       subtitle = "Seven selected restaurants; cheaper menus remain within a higher budget",
       x = "Maximum menu budget per person", y = "Number of restaurants", fill = NULL,
       caption = "2026 Dining Days list + linked menus checked October 7, 2026") +
  theme_minimal(base_size = 12) + theme(legend.position = "bottom")

restaurant_plot <- minimum_prices |>
  mutate(meal = if_else(meal == "LUNCH", "Lunch", "Dinner")) |>
  ggplot(aes(x = minimum_price, y = reorder(restaurant, minimum_price), color = meal)) +
  geom_point(aes(shape = meal), size = 3, position = position_dodge(width = 0.5)) +
  scale_x_continuous(breaks = c(20, 30, 40), labels = c("$20", "$30", "$40"), limits = c(18, 42)) +
  scale_color_manual(values = c("Dinner" = "#B54F26", "Lunch" = "#286789")) +
  labs(title = "Where could you go?", subtitle = "Cheapest listed menu at each of the seven selected restaurants",
       x = "Menu price per person", y = NULL, color = NULL, shape = NULL,
       caption = "2026 Dining Days list + linked menus checked October 7, 2026
Prices exclude tax, tips, and optional extras; lunch and dinner dishes can differ.") +
  theme_minimal(base_size = 12) + theme(legend.position = "bottom")

write_csv(restaurants, "data/processed/restaurant-options.csv")
write_csv(reviewed, "data/processed/reviewed-cuisine-options.csv")
write_csv(choices, "results/tables/choices-by-meal-price.csv")
write_csv(minimum_prices, "results/tables/restaurant-minimum-prices.csv")
write_csv(budget_choices, "results/tables/choices-by-cuisine-budget.csv")
ggsave("results/figures/cuisine-budget.png", budget_plot, width = 9, height = 4.8, dpi = 180)
ggsave("results/figures/restaurant-prices.png", restaurant_plot, width = 9, height = 5.2, dpi = 180)

write_csv(budget_changes, "results/tables/budget-changes.csv")
write_csv(meal_comparison, "results/tables/lunch-dinner-comparison.csv")
write_csv(meal_prices, "results/tables/paired-menu-prices.csv")
capture.output(sessionInfo(), file = "results/session-info.txt")
