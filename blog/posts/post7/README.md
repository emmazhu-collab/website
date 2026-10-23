# Blog 7: Texas and California unemployment recovery

This post compares monthly unemployment rates in Texas and California from January 2019 through December 2023. It uses one BLS measure from FRED and checks recovery against two state-specific pre-pandemic benchmarks.

## Folder structure

All paths below start from `blog/posts/post7/`.

```text
post7/
├── index.qmd                         Article and interactive Plotly chart
├── README.md                         Data notes and replication instructions
├── code/
│   ├── analysis.R                    Recovery definitions, checks, and chart
│   ├── download_data.R               Optional FRED API download and validation
│   └── run_analysis.R                Rebuilds aggregate tables and chart HTML
├── data/source/
│   ├── unemployment_tx_ca.csv        Saved 120 state-month observations
│   └── series_metadata.csv           Series details and access date
└── results/
    ├── tables/                       Aggregate summaries and monthly recovery gaps
    ├── interactive_recovery.html     Standalone chart for review
    └── interactive_recovery_files/   Supporting HTML widget files
```

## Data

The data are the U.S. Bureau of Labor Statistics monthly unemployment-rate series available through FRED: [Texas, TXUR](https://fred.stlouisfed.org/series/TXUR) and [California, CAUR](https://fred.stlouisfed.org/series/CAUR). Both series are seasonally adjusted and measured in percent. The saved data contain 60 months per state. FRED can revise historical observations; `series_metadata.csv` records when this snapshot was retrieved.

The article uses two definitions of a pre-pandemic rate: the average for 2019 and the February 2020 rate. It identifies each state's highest rate from March through December 2020, then finds the first month after the peak at or below each benchmark. The analysis checks whether the first return begins a run of three consecutive months at or below the benchmark. The earlier-cutoff table checks whether a return would have been observed by December 2021 or December 2022. A return not observed before a cutoff is right-censored; it is not evidence that the rate later moved in the opposite direction.

## Replication instructions

Open the website project in RStudio, or run the commands below from the `website-recovered` project root. Use R 4.5 or newer and install any missing packages once:

```r
install.packages(c("fredr", "dplyr", "readr", "lubridate", "tibble", "tidyr", "plotly", "htmlwidgets", "knitr"))
```

The saved CSV is the exact input for this article. Rebuild its aggregate tables and interactive chart plus supporting files without contacting FRED:

```sh
Rscript blog/posts/post7/code/run_analysis.R
```

To download a fresh snapshot instead, set `FRED_API_KEY` in your local R environment, restart R, and run:

```sh
Rscript blog/posts/post7/code/download_data.R
Rscript blog/posts/post7/code/run_analysis.R
```

The downloader checks the series frequency, units, seasonal adjustment, date coverage, missing values, and duplicate state-month keys. It reads the API key from the environment and never prints or saves it. FRED may revise historical data, so a new download can change the results. Review the updated tables before replacing the values used in the article.

To render this post as part of the website when you are ready, run from the project root:

```sh
quarto render blog/posts/post7/index.qmd
```

Rendering also requires the R packages listed above. The article uses the saved CSV and does not need a live FRED request. The website project writes rendered pages to `docs/`.

The article links to `README.html`, a browser-readable copy of these instructions. If you edit this README, refresh that copy from the project root with:

```sh
quarto render blog/posts/post7/README.md --to html
```

## Current aggregate results

Both states peaked in April 2020: 12.8% in Texas and 16.1% in California. California first returned to its 2019 average (4.09%) in June 2022 and to its February 2020 rate (4.40%) in April 2022. Texas did not reach either benchmark by December 2023. The ordering is the same under both benchmarks, but California's return date changes by two months. See `results/tables/` for the complete calculated tables.

These are descriptive unemployment-rate comparisons. They do not show that employment levels fully recovered or explain why the two states followed different paths.

## Interactive chart

The article contains one Plotly chart with one dropdown listing four view and benchmark combinations. The unemployment-rate view shows the original state rates and the selected benchmark lines. The recovery-gap view recalculates each monthly value as the unemployment rate minus that state's benchmark, in percentage points. Zero means the rate equals its benchmark. The benchmark choice changes the gap series itself. Hover text reports the state, rate, benchmark, and gap; first-return markers also report whether the three-month check is met. The dropdown updates all chart traces and axis settings together using Plotly’s built-in menu updates. The article contains exactly one chart.

The saved `results/tables/recovery_gaps.csv` contains the monthly gap for both states under both benchmarks. For example, in April 2022 Texas's rate was 3.9% and California's was 4.3%. Against February 2020, the gaps were +0.3 and -0.1 percentage points, respectively. Texas had the lower rate, but California was closer to its own benchmark and had already moved below it.

