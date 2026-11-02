# Blog 9: Predicting Stock Returns with Gradient Boosting

This project compares the classroom XGBoost model, a simpler XGBoost model, and a zero-return forecast. It also compares two top-10 stock portfolios with passive SPY. The article is `index.qmd`.

## Files

- `UPenn_XGBoostStockPrediction copy (1).R`: unchanged professor's script, kept as a reference. Run the new script below to reproduce this article.
- `Blog9_StockPrediction.R`: downloads data only if the saved snapshot is missing, prepares features, fits both models, and saves the results and figures.
- `data/source/yahoo_prices.csv`: saved daily stock and SPY price snapshot. `SOURCE.txt` records the source and download date.
- `results/tables/data_coverage.csv`: checks each stock against the SPY trading calendar. The script stops if any requested stock has incomplete prices.
- `results/tables/study_window.csv` and `sample_counts.csv`: dates, stock count, training/test rows, and rows removed at the split boundary.
- `results/tables/model_settings.csv`: model specifications.
- `results/tables/test_predictions.csv`: actual forward returns and all three forecasts on identical test rows.
- `results/tables/prediction_metrics.csv`: RMSE and MAE, in decimal returns. The article displays percentage points.
- `results/tables/portfolio_holdings.csv`: top-10 stocks, normalized weights, and holding dates for each strategy.
- `results/tables/portfolio_returns.csv`: non-overlapping holding-period returns and cumulative growth, before and after the cost assumption.
- `results/tables/investment_metrics.csv`: cumulative returns and annualized Sharpe ratios.
- `results/figures/`: two PNG figures used in the article.
- `results/session-info.txt`: R and package versions from the successful run.

## Run the analysis

Open the existing website RStudio project. Install missing packages once in the **R Console**:

```r
install.packages(c("tidyverse", "tidyquant", "slider", "xgboost", "knitr", "rmarkdown"))
```

From the website project root, run:

```r
source("blog/posts/post9/Blog9_StockPrediction.R")
```

Alternatively, from the `post9` folder in a **Terminal**, run:

```bash
Rscript Blog9_StockPrediction.R
```

The script works from either of these directories. It does not require an API key. With the saved CSV present, it needs no market-data download. A new download needs internet access and may give different results because vendors revise prices. The script overwrites generated results, but reuses the saved data and never modifies the professor's script. Use the recorded package versions for the closest numerical reproduction; XGBoost releases may differ.

To display the article after running the analysis, render `index.qmd` in RStudio, or run from the website root:

```bash
quarto render blog/posts/post9/index.qmd
```

Rendering reads saved tables and PNGs only. It does not fit models or download prices.

## Model and timing choices

The stock list is copied from the professor's script. Prices begin in January 2022; the fixed exclusive download end is November 1, 2026. Dates actually returned are recorded in `study_window.csv`.

The original specification uses 300 trees, depth 5, learning rate 0.05, gamma 0, and `min_child_weight = 10`. This last parameter matches `min_n = 10` in the classroom parsnip engine. Both models use the same 14 predictors: open, high, low, close, volume, adjusted price, daily stock return, SPY return, three momentum ratios, lagged volatility, a short-term ratio, and excess daily return. The classroom formula included price levels and volume as well as the named engineered features. Date and ticker are identifiers, not predictors.

The older-price/recent-price momentum ratios are preserved exactly, even though they reverse conventional momentum. The volatility calculation uses 22 lagged daily returns, matching `.before = 21`. The target is also preserved: adjusted price at t+20 divided by adjusted price at t+1, minus one. This is **19 trading-day intervals**, not 20 close-to-close returns.

The one improvement attempt reduces depth to 2 and raises minimum child weight to 50. Everything else is unchanged. These settings were chosen before inspecting the test results, with no hyperparameter search or test-based model selection. Shallower trees may reduce overfitting but can also miss useful relationships. Both models use the native XGBoost interface with squared-error regression, histogram trees, all rows/columns, seed 123, and 300 rounds. This reproduces the classroom specification, not a promise of bit-identical results from another package version.

Training signals precede January 1, 2024. Their target exit dates must also precede that boundary. Test signals begin January 2, 2024. This purge prevents training labels from extending into the test period. Test windows overlap for daily prediction scoring, so the rows are dependent; no independent-observation significance test is claimed. Models are fitted once, with no test-period retraining.

## Portfolio corrections applied to both models

Signals use information through that day's close, and entry occurs at the next close. The next signal occurs 19 trading days later. Its entry coincides with the previous exit, giving adjacent, non-overlapping 19-interval holdings. The final partial block is not used. SPY uses exactly the same first entry, last exit, and intermediate dates.

Each portfolio selects the highest 10 forecasts. Negative forecasts receive zero weight; positive forecasts are normalized to sum to one. If all are nonpositive, the ten receive equal weights. Ties are broken by ticker. A regular `if` is used for this group-level decision: the original scalar-condition `ifelse` can recycle a single weight instead of producing the intended normalized vector. Holding-period weights are buy-and-hold weights, not rebalanced daily.

The original first-of-calendar-month schedule did not necessarily match its forward target windows. The original SPY monthly calculation also reset the lag within each month and compounded from a different starting point. Here all returns use aligned entry and exit prices. Sharpe is mean block return divided by block-return standard deviation, multiplied by `sqrt(252/19)`. The risk-free rate is assumed to be zero; this is not a Treasury-adjusted Sharpe or proof of alpha.

The cost sensitivity charges 0.1% on each purchase and sale. Model portfolios are assumed fully sold and repurchased each block, even when holdings repeat. This is a conservative full-turnover assumption, not measured execution cost. Passive SPY pays once on entry and once on final exit. Taxes, price impact, and execution uncertainty are excluded.

## Limits and sources

These are retrospective experiments in a fixed list of large surviving companies. The list was not reconstructed at each historical date, and the saved adjusted prices are not a point-in-time archive. Corporate actions and later adjustments can affect historical levels. Thus chronology and label purging improve evaluation but do not establish a completely hindsight-free trading strategy. Portfolio gains can reflect market exposure and concentration rather than stock-picking skill. Three years of testing in one market episode cannot establish reliable future profits.

- [Yahoo Finance](https://finance.yahoo.com/): price source.
- [tidyquant data documentation](https://business-science.github.io/tidyquant/reference/tq_get.html): download interface.
- [parsnip XGBoost documentation](https://parsnip.tidymodels.org/reference/details_boost_tree_xgboost.html): parameter mapping.
