# Blog 2: University City Dining Days

## Question

Which meal and price group offered the most restaurant choices in the 2026 University City Dining Days event? This post compares lunch and dinner menus at $20, $30, and $40 to help diners decide where to start looking.

## Data and method

The source is the [University City Dining Days page](https://www.universitycity.org/diningdays/), first accessed on September 19, 2026. The post looks at the 2026 list, not current offers.

The R script uses `rvest` to collect restaurant names, links, meals, and prices. It removes extra spaces and empty names, checks for duplicate entries within each group, and counts the options. Each row is one restaurant at one meal and price. A restaurant can appear for both lunch and dinner. Separate cafe deals are left out.

The script requests one public page per run and does not bypass access restrictions. Avoid running it repeatedly. Since it reads a live page, future website changes may require updating the selectors in `analysis.R`. The saved CSV files record the results from the last run; they are not the input to the scraper.

## Files

All paths below start from this post folder.

| File | Purpose |
| --- | --- |
| `index.qmd` | Article text and links to the figure |
| `analysis.R` | Data collection, cleaning, counts, and plotting |
| `data/processed/restaurant-options.csv` | Cleaned restaurant options |
| `results/choices-by-meal-price.csv` | Restaurant counts for the six groups |
| `graph/restaurant-choices.png` | Bar chart used in the article |

## How to run

1. Open `studentname-website.Rproj` from the main repository folder in RStudio.
2. Install any missing packages in the R Console:

   ```r
   install.packages(c("rvest", "tidyverse", "knitr", "rmarkdown"))
   ```

3. Open `blog/posts/post2/index.qmd` and click **Render**. An internet connection is required.

Render runs `analysis.R`, updates the two CSV files and the figure, and creates the article webpage. The website output is in `docs/blog/posts/post2/` from the main repository folder. The webpage shows the article and figure, while the analysis code stays in `analysis.R`.

To run only the analysis, open `analysis.R`, choose **Session → Set Working Directory → To Source File Location**, and run `source("analysis.R")` in the R Console.

## Reading the results

The chart compares exact price groups, not all restaurants below a maximum budget. It counts choices, not food quality, portion sizes, or available tables. Menu prices exclude tax and tips. Check the latest menus and event dates before planning a visit.
