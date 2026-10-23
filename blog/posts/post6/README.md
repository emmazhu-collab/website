# Blog 6: Does One Year of Income Tell the Whole Story?

This tutorial uses Python and SQLite to match PSID fathers and children, construct earnings near age 40, and compare single-year with three-year-average IGE estimates.

## Files

- `index.qmd`: article, teaching examples, and interpretation.
- `code/same_age_analysis.py`: analysis script.
- `sql/same_age_sample.sql`: SQL summaries and father-child matching.
- `data/cpi_same_age.csv`: public monthly CPI data for 1993–2022.
- `results/life_cycle.csv`: saved aggregate results for the separate 2014/2022 comparison in the article.
- `figures/same-age-ige.png`: main IGE comparison for the 321-pair sample.
- `results/figures/life-cycle.png`: supplementary comparison using a separate 140-pair sample.

PSID microdata are not included. Download the needed files from the [PSID Data Center](https://simba.isr.umich.edu/Zips/ZipMain.aspx) using your own registered account. Follow the PSID Conditions of Use, keep the original files in the local sibling `blog6/data/raw/` folder, and do not upload individual records to GitHub or an AI service. See the standalone Blog 6 README for required filenames and variables.

## Reproduce the analysis

From the `website-recovered` project folder, run this command in Terminal:

```sh
/opt/anaconda3/bin/python blog/posts/post6/code/same_age_analysis.py
```

The script reads the local PSID files, applies the documented age, role, and income rules, and saves results to a new timestamped folder under `blog/posts/post6/results_same_age/`. Outputs include aggregate checks, IGE estimates, bootstrap intervals, and figures. The script does not write personal IDs or individual earnings records, change the article, or render the website.

For each person's three selected records, SQL uses `AVG(age)` as the mean of their three interview ages. The father-child age-gap rule compares these mean ages, as well as the ages of the single-year observations. This mean summarizes three measurement ages; it is not one specific interview age.

The article's supplementary figure uses the saved 140-pair comparison of children's 2014 and 2022 earnings in `results/life_cycle.csv`. The current script also creates an age-stage check, but it selects observations by age from the main sample and does not recreate that exact 2014/2022 comparison. The saved CSV and PNG are therefore needed to reproduce the supplementary figure as shown.

## Results and interpretation

The main analysis covers available earnings years from 1993 through 2022. It uses the same 321 father-child pairs and 249 fathers for both income measures. The single-year IGE is 0.170 (95% father-cluster bootstrap interval: 0.030–0.354); the three-year-average IGE is 0.291 (0.151–0.444). The paired difference is 0.121 (-0.037–0.268), so the estimates are numerically different but the interval does not establish a clear difference. The separate life-stage check uses 140 pairs and compares child earnings in 2014 and 2022 while holding the father's three-year average fixed. Its difference interval includes zero, and age and calendar year change together, so it is exploratory rather than causal.

Interview age approximates age when earnings were received, since income refers to the prior year. A three-year average is not lifetime earnings. Requiring positive repeated earnings also selects the sample, so results should not be treated as representative of all families or as a causal effect.
