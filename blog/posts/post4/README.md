# Blog 4: Two Kinds of Gas, Two Different Price Stories

## Question

How have U.S. gasoline and natural gas prices changed, and how similar are their movements? Three figures compare gasoline prices, natural gas prices, and their inflation-adjusted indexes from January 2000 through August 2026.

## Data

I use `fredr` to download data from the FRED API. The included files were downloaded on October 5, 2026.

| FRED series | Source and meaning | Original frequency and units |
| --- | --- | --- |
| [GASREGW](https://fred.stlouisfed.org/series/GASREGW) | EIA, U.S. regular gasoline retail price, including taxes | Weekly; dollars per gallon |
| [DHHNGSP](https://fred.stlouisfed.org/series/DHHNGSP) | EIA, Henry Hub natural gas spot price | Daily; dollars per million BTU |
| [CPIAUCNS](https://fred.stlouisfed.org/series/CPIAUCNS) | BLS, CPI-U for all items, U.S. city average | Monthly; 1982–1984 = 100 |

The code requests monthly averages for both fuels (`frequency = "m"`, `aggregation_method = "avg"`). CPI is already monthly. Each series has 320 months, and none is seasonally adjusted.

Natural gas is missing in March 2004, and CPI is missing in October 2025. These stay blank in the graphs. There are 318 months with both real-price indexes available.

## Files

Paths below start from this post folder.

| File or folder | Purpose |
| --- | --- |
| `index.qmd` | Article, figure links, and a hidden call to the analysis script |
| `analysis.R` | API download, data preparation, calculations, and graphs |
| `data/gasoline-monthly.csv` | Monthly gasoline prices returned by FRED |
| `data/natural-gas-monthly.csv` | Monthly natural gas prices returned by FRED |
| `data/cpi-monthly.csv` | Monthly CPI values returned by FRED |
| `data/download-date.csv` | Date the saved inputs were downloaded |
| `results/monthly-comparison.csv` | Matched prices, CPI, real prices, and indexes |
| `results/price-summary.csv` | Peak months, peak prices, and final-month values |
| `results/missing-months.csv` | Months with a missing input |
| `graph/gasoline.png` | Gasoline price figure |
| `graph/natural-gas.png` | Natural gas price figure |
| `graph/real-price-comparison.png` | Comparison on the same real-price index scale |

## How to run

1. Open `studentname-website.Rproj` from the main repository folder in RStudio.
2. Install missing packages in the R Console:

   ```r
   install.packages(c("tidyverse", "fredr", "knitr", "rmarkdown"))
   ```

3. Open `blog/posts/post4/index.qmd` and click **Render**.

Render reads the saved data and runs `analysis.R` to update the results, three figures, and article numbers. With the files and packages installed, you do not need an API key or internet connection. The webpage shows only the article and graphs. It is saved in `docs/blog/posts/post4/` from the repository root.

To run just the analysis, open `analysis.R`, choose **Session → Set Working Directory → To Source File Location**, then run `source("analysis.R")` in the R Console.

## Download fresh data

Set your own FRED API key in your local `.Renviron` as `FRED_API_KEY=your_key`, then restart R. Do not put the real key in code or upload the `.Renviron` file.

In `analysis.R`, set `refresh_data <- TRUE` and run the script. This downloads the three series again for the same dates and replaces the saved files. Then set it back to `FALSE`. If an input CSV is missing, the script also needs a key to download the data.

Use the included CSV files to reproduce this version. FRED can revise data, so after downloading again, check that the article, titles, and missing-month notes still match the results.

## Calculations and limits

Real price = nominal price × CPI in August 2026 ÷ CPI in the observation month.

Real price index = 100 × real price ÷ real price in January 2000.

The first two graphs show nominal prices in their original units. The third removes general inflation and compares changes from the same starting month. A value of 150 means 50% above that fuel's January 2000 real price. The index does not compare energy costs per unit of heat, and the choice of starting month affects the index levels.

Henry Hub is a wholesale benchmark, not a household bill. Monthly averages hide daily and weekly changes. These graphs do not identify the causes of price changes.

Sources: U.S. Energy Information Administration (GASREGW and DHHNGSP) and U.S. Bureau of Labor Statistics (CPIAUCNS), retrieved through FRED, Federal Reserve Bank of St. Louis. Series links are listed above.
