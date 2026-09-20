# Xuanru Zhu's Website

This repository contains my personal website and blog posts for AEDS 6400.

## Blog 2: University City Dining Days

This post uses R and `rvest` to collect restaurant information from the [University City Dining Days website](https://www.universitycity.org/diningdays/). It compares the number of restaurant choices for lunch and dinner at $20, $30, and $40.

The analysis uses the 2026 restaurant list, first accessed on September 19, 2026. Each row is one restaurant at one meal and price. A restaurant can appear in more than one group.

## Where to find the files

| File or folder | Contents |
| --- | --- |
| `blog/posts/post2/index.qmd` | Blog 2 text and R code |
| `blog/posts/post2/data/processed/restaurant-options.csv` | Cleaned restaurant data |
| `blog/posts/post2/results/choices-by-meal-price.csv` | Restaurant counts by meal and price |
| `docs/` | Generated webpages and figures |
| `_quarto.yml` | Website settings |

## How to run the code

You need R, RStudio, and an internet connection.

1. Download this repository and open `studentname-website.Rproj` in RStudio.
2. Install any missing packages in the R Console:

   ```r
   install.packages(c("rvest", "tidyverse", "knitr", "rmarkdown"))
   ```

3. Open `blog/posts/post2/index.qmd` and click **Render**.

This updates the two CSV files and the webpage in `docs/`. The code reads the live website, so changes to the website may affect the results.
