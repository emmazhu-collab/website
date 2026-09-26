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

## How to run the code

You need R, RStudio, and an internet connection.

1. Download this repository and open `studentname-website.Rproj` in RStudio.
2. Install any missing packages in the R Console:

   ```r
   install.packages(c("rvest", "tidyverse", "knitr", "rmarkdown"))
   ```

3. Open `blog/posts/post2/index.qmd` and click **Render**.

This updates the two CSV files and the webpage in `docs/`. The code reads the live website, so changes to the website may affect the results.

## Blog 3: Education and Unemployment

This post compares unemployment by education using IPUMS CPS Basic Monthly data for January 2020–2026. It uses the CPS person weight (WTFINL) and focuses on civilians ages 25–64 in the labor force.

- `blog/posts/post3/index.qmd`: text and R code.
- `blog/posts/post3/data/`: folder for the CPS data and XML data dictionary.
- `blog/posts/post3/results/`: two summary tables and three figures saved by the code.

### How to run Blog 3

1. Sign in to [IPUMS CPS](https://cps.ipums.org/cps/) and select January Basic Monthly samples for 2020–2026. Include YEAR, MONTH, AGE, EDUC, EMPSTAT, and WTFINL.
2. Download the fixed-width data and DDI (XML) dictionary. Put them in `blog/posts/post3/data/` as `cps_00001.dat.gz` and `cps_00001.xml`. If your extract has a different name, change both paths in the first code chunk.
3. Install `ipumsr` and `tidyverse` if needed. Open `blog/posts/post3/index.qmd` in RStudio and click **Render**.

The raw CPS microdata are not included in this GitHub repository. To reproduce the analysis, users need to download their own IPUMS CPS extract. The summary tables and figures used in the post are saved in the `results/` folder.
