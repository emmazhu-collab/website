# Xuanru Zhu's Quarto website

## Blog 2: University City Dining Days

This post asks which meal and price group had the most restaurant choices in the 2026 Dining Days event.

### Files

- `blog/posts/post2/index.qmd`: the blog text and R code.
- `blog/posts/post2/data/processed/restaurant-options.csv`: the cleaned restaurant data.
- `blog/posts/post2/results/choices-by-meal-price.csv`: the number of restaurants in each group.
- `docs/`: the website files made by Quarto.

### Run the analysis

You need R, Quarto, and the R packages `rvest`, `tidyverse`, `knitr`, and `rmarkdown`.

1. Open `studentname-website.Rproj` in RStudio.
2. Open `blog/posts/post2/index.qmd`.
3. Click **Render**.

You can also run this command from the project folder:

```sh
quarto render blog/posts/post2/index.qmd
```

The code reads the webpage, collects the restaurant data, counts the choices, and saves two CSV files. You need an internet connection. File paths in the code start from the `post2` folder.

### Data source and limits

Source: https://www.universitycity.org/diningdays/

The page was first checked on September 19, 2026. It showed the 2026 restaurant list. These deals may no longer be available. If the page changes, check the six CSS selectors and the results again. Avoid running the download step too often. The code does not bypass access restrictions.

Each row is one restaurant at one meal and price. A restaurant can appear for both lunch and dinner. Separate cafe deals are left out. The chart compares each price group, not all options below a maximum budget. Menu prices do not include tax or tips.
