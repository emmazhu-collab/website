# Optional: run once from the post2 folder when checking a new list.
# Normal reproduction uses saved inputs and does not run this file.
library(rvest)
library(tidyverse)
url <- "https://www.universitycity.org/diningdays/"

# Read one public page; never bypass access restrictions.
page <- read_html(url)
dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
# Save what this new request returned, without changing the article's inputs.
snapshot <- paste0("data/raw/dining-days-", Sys.Date(), ".html")
xml2::write_html(page, snapshot)


meal_headings <- page |>
  html_elements("h1.uagb-heading-text") |>
  html_text2()

price_headings <- page |>
  html_elements("h2.uagb-heading-text") |>
  html_text2()



section_selectors <- c(
  ".uagb-block-a013eba9, .uagb-block-278fad71",
  ".uagb-block-4a407aab, .uagb-block-85b34e24",
  ".uagb-block-d61ca5e5, .uagb-block-56971bc4, .uagb-block-9b2f9222, .uagb-block-b6c4b5ed",
  ".uagb-block-ff275771, .uagb-block-2bd8e149",
  ".uagb-block-8d01d505, .uagb-block-f4846327, .uagb-block-78266301",
  ".uagb-block-5f762f09"
)

stopifnot(length(price_headings) == 6,
          identical(meal_headings[1:2], c("DINNER", "LUNCH")))

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

stopifnot(nrow(restaurants_raw) > 0, !anyNA(restaurants_raw),
          all(table(factor(restaurants_raw$meal, levels = c("DINNER", "LUNCH"))) > 0))
write_csv(restaurants_raw, paste0("data/raw/main-page-", Sys.Date(), ".csv"))
message("New HTML and extracted rows saved under data/raw/. Historical inputs were not changed.")
