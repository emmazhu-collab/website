# Blog 3: Education and Unemployment

## Question

How does unemployment differ by education in the United States? The post compares education groups in January 2026, follows the same groups from January 2020 to January 2026, and compares four age groups in January 2026.

## Data and method

The source is [IPUMS CPS](https://cps.ipums.org/cps/), Version 13.0. I use the Basic Monthly January samples for 2020–2026. The analysis includes civilians ages 25–64 who are employed or unemployed. People outside the labor force are excluded.

Education is grouped into less than high school, high school, some college or an associate degree, and a bachelor's degree or higher. Employment status comes from `EMPSTAT`, and education comes from `EDUC`. Unemployed people include those on temporary layoff.

The script uses the person weight `WTFINL`. Within each group, the unemployment rate is `100 * weighted.mean(unemployed, WTFINL)`. This gives the weighted percentage of the labor force who are unemployed. The figures describe January, not annual averages or seasonally adjusted rates.

## Files

All paths below start from this post folder.

| File | Purpose |
| --- | --- |
| `index.qmd` | Article text and links to the figures |
| `analysis.R` | Data preparation, weighted rates, and plotting |
| `data/cps_00001.dat.gz` | Raw CPS data, downloaded separately |
| `data/cps_00001.xml` | Matching data dictionary used to read the data |
| `results/rates-by-year.csv` | Rates and sample counts by year and education |
| `results/rates-by-age.csv` | Rates and sample counts by age and education in 2026 |
| `graph/education-2026.png` | Education comparison for January 2026 |
| `graph/education-trend.png` | January comparison over time |
| `graph/education-by-age.png` | Education comparison within age groups |

## Get the data

1. Sign in to IPUMS CPS and select the January Basic Monthly samples for each year from 2020 through 2026. Do not select ASEC samples.
2. Include `YEAR`, `MONTH`, `AGE`, `EDUC`, `EMPSTAT`, and `WTFINL`.
3. Download the fixed-width data (`.dat.gz`) and its DDI dictionary (`.xml`). Put both in this post's `data/` folder.
4. The script expects `cps_00001.dat.gz` and `cps_00001.xml`. If your extract has a different name, update the two file paths in `analysis.R`. Use the dictionary that belongs to your downloaded extract.

Raw CPS microdata are excluded from Git. Other readers need to download their own extract under the [IPUMS terms](https://cps.ipums.org/cps/terms.shtml).

## How to run

1. Open `studentname-website.Rproj` from the main repository folder in RStudio.
2. Install any missing packages in the R Console:

   ```r
   install.packages(c("ipumsr", "tidyverse", "knitr", "rmarkdown"))
   ```

3. Open `blog/posts/post3/index.qmd` and click **Render**.

Render runs `analysis.R`, updates the two summary tables and three figures, and creates the article webpage. The website output is in `docs/blog/posts/post3/` from the main repository folder. Code is kept in the separate script and is not shown on the webpage. Once the data and packages are installed, the analysis reads local files and does not download data again.

To run only the analysis, open `analysis.R`, choose **Session → Set Working Directory → To Source File Location**, and run `source("analysis.R")` in the R Console.

## Reading the results

`sample_n` is the number of survey observations in each group, not a population total. `rate` is the weighted unemployment percentage. The figures show differences between groups; they do not prove that education causes lower unemployment. Small groups have less precise estimates, and the analysis does not test statistical significance.

Data citation: Sarah Flood et al. (2025). *IPUMS CPS: Version 13.0* [dataset]. Minneapolis, MN: IPUMS. [doi:10.18128/D030.V13.0](https://doi.org/10.18128/D030.V13.0).
