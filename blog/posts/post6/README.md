# Blog 6: Does One Year of Income Tell the Whole Story?

This post teaches how Python and SQLite can connect PSID fathers and children, build earnings measures near age 40, and compare single-year with three-year-average IGE estimates.

## Files for the article

- `index.qmd`: article and teaching examples.
- `code/same_age_analysis.py`: same-age analysis script adapted to this website folder.
- `sql/same_age_sample.sql`: SQL used for earnings summaries and parent-child matching.
- `data/cpi_same_age.csv`: public CPI input for 1993–2022.
- `figures/same-age-ige.png`: main figure for 321 father-child pairs.
- `results/life_cycle.csv` and `results/figures/life-cycle.png`: saved aggregate results and figure for the separate 140-pair 2014/2022 comparison.

The full PSID data inputs are not included. Get your own files from the [PSID Data Center](https://simba.isr.umich.edu/Zips/ZipMain.aspx), follow the [PSID Conditions of Use](https://simba.isr.umich.edu/U/CondUse.aspx), and keep the original files private. In this local setup, the script finds the sibling `blog6/data/raw/` folder. If using a different folder, pass it with `--raw-dir`. The standalone [Blog 6 analysis repository](https://github.com/emmazhu-collab/blog6) has the input list, codebooks, and full replication notes.

## Reproduce the main analysis

From the `website-recovered` project folder, run:

```sh
python3 blog/posts/post6/code/same_age_analysis.py
```

This writes aggregate outputs and figures to a new timestamped folder under `blog/posts/post6/results_same_age/`. It does not save IDs or individual earnings, edit the article, or render the website. Install the packages in the standalone project's `requirements.txt` if needed.

The checked-in article snapshot uses 321 father-child pairs and 249 unique fathers. The single-year IGE is 0.170 (95% father-cluster bootstrap interval: 0.030–0.354); the three-year-average IGE is 0.291 (0.151–0.444). Their difference is 0.121 (-0.037–0.268), with an interval that includes zero.

## The separate life-cycle figure

The article's 2014/2022 figure uses a different, 140-pair sample and an earlier income construction. Its saved CSV and PNG are kept here so the website displays the published result. The current same-age script creates a different age-stage check and does not reproduce that 2014/2022 calculation. To reproduce the published figure, use `code/analysis.py` and `sql/build_sample.sql` in the standalone [Blog 6 analysis repository](https://github.com/emmazhu-collab/blog6); these are retained because the method cannot be safely combined with the main script without checking it on the restricted local data.

The 2014/2022 comparison reports IGEs of 0.186 and 0.244, mean child interview ages of 27.5 and 35.5, and a difference interval of -0.111 to 0.232. Age and calendar year both change, so it is exploratory and does not identify a causal age effect.

## Limits and data use

Income refers to the previous calendar year, so interview age approximates earnings age. Repeated positive-earnings requirements select the sample; it may not represent all families. A three-year average is not lifetime income, and age matching cannot remove all temporary shocks or cohort differences. IGE describes an association, not a causal effect.

PSID raw data are not included in this website project. Do not commit or upload individual-level PSID files or send them to an AI/LLM service. Only the public CPI data and aggregate figure/results needed for the article are included.
