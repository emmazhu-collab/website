# Run from this post folder, or use source("analysis.R", chdir = TRUE).
# Rendering index.qmd also runs this script.
dir.create("graph", showWarnings = FALSE)
dir.create("results", showWarnings = FALSE)
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)

library(rvest)
library(tidyverse)

url <- "https://www.universitycity.org/diningdays/"
url

page <- read_html(url)

page |>
  html_element("title") |>
  html_text2()

meal_headings <- page |>
  html_elements("h1.uagb-heading-text") |>
  html_text2()

price_headings <- page |>
  html_elements("h2.uagb-heading-text") |>
  html_text2()

meal_headings
price_headings

restaurant_cards <- page |>
  html_elements("figure.wp-block-uagb-image__figure")

restaurant_cards |>
  html_element("figcaption a") |>
  html_text2() |>
  head()

section_selectors <- c(
  ".uagb-block-a013eba9, .uagb-block-278fad71",
  ".uagb-block-4a407aab, .uagb-block-85b34e24",
  ".uagb-block-d61ca5e5, .uagb-block-56971bc4, .uagb-block-9b2f9222, .uagb-block-b6c4b5ed",
  ".uagb-block-ff275771, .uagb-block-2bd8e149",
  ".uagb-block-8d01d505, .uagb-block-f4846327, .uagb-block-78266301",
  ".uagb-block-5f762f09"
)

section_meals <- c(
  rep(meal_headings[1], 3),
  rep(meal_headings[2], 3)
)

restaurant_names <- c()
restaurant_urls <- c()
meals <- c()
prices <- c()

for (i in 1:6) {
  cards <- page |>
    html_elements(section_selectors[i]) |>
    html_elements("figure.wp-block-uagb-image__figure")

  links <- cards |>
    html_element("figcaption a")

  restaurant_names <- c(restaurant_names, html_text2(links))
  restaurant_urls <- c(restaurant_urls, html_attr(links, "href"))
  meals <- c(meals, rep(section_meals[i], length(cards)))
  prices <- c(prices, rep(price_headings[i], length(cards)))
}

restaurants_raw <- tibble(
  restaurant = restaurant_names,
  meal = meals,
  price = prices,
  url = restaurant_urls
)

head(restaurants_raw)

restaurants <- restaurants_raw |>
  mutate(
    restaurant = str_squish(restaurant),
    meal = str_squish(meal),
    price = str_squish(price)
  ) |>
  filter(restaurant != "")

nrow(restaurants_raw)
nrow(restaurants)

restaurants |>
  count(meal, price, url) |>
  filter(n > 1)

choices <- restaurants |>
  count(meal, price, sort = TRUE)


choice_plot <- choices |>
  mutate(option = paste(meal, price)) |>
  ggplot(aes(x = reorder(option, n), y = n)) +
  geom_col(fill = "#286789") +
  coord_flip() +
  labs(
    title = "Dinner at $40 offered the most choices",
    subtitle = "Restaurants in the 2026 Dining Days event",
    x = NULL,
    y = "Number of restaurants",
    caption = "Source: University City District | 2026 participant list"
  ) +
  theme_minimal(base_size = 13)


write_csv(restaurants, "data/processed/restaurant-options.csv")
write_csv(choices, "results/choices-by-meal-price.csv")
ggsave("graph/restaurant-choices.png", choice_plot, width = 8, height = 4.8, dpi = 300)
