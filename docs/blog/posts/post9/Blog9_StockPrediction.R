# Blog 9: run from post9, or source this file from the website project root.
# Original classroom script is retained unchanged alongside this file.
# No model fitting or downloads occur when index.qmd is rendered.
suppressPackageStartupMessages({
  library(tidyverse)
  library(tidyquant)
  library(slider)
  library(xgboost)
})
set.seed(123)
post <- if (file.exists('Blog9_StockPrediction.R')) '.' else 'blog/posts/post9'
stopifnot(file.exists(file.path(post, 'Blog9_StockPrediction.R')))
p <- function(...) file.path(post, ...)
for (d in c('data/source', 'results/tables', 'results/figures'))
  dir.create(p(d), recursive = TRUE, showWarnings = FALSE)
save_table <- function(x, name) write_csv(x, p('results/tables', name))

# Fixed window; November 1 is an exclusive end date. Use saved snapshot on reruns.
# Delete/rename the snapshot ONLY if deliberately obtaining a new data vintage.
tickers <- c(
  'AAPL','MSFT','NVDA','GOOG','META','AMZN','AVGO','ORCL','ADBE','CRM',
  'CSCO','AMD','INTC','QCOM','TXN','IBM','NOW','INTU','AMAT','MU',
  'JPM','BAC','WFC','GS','MS','BLK','C','SCHW','SPGI','AXP','USB','PNC','TFC','COF',
  'UNH','JNJ','LLY','PFE','MRK','ABBV','TMO','DHR','ABT','BMY','AMGN','GILD','CVS','ISRG','MDT',
  'TSLA','HD','MCD','NKE','SBUX','LOW','TJX','BKNG','CMG','ORLY',
  'WMT','COST','PG','KO','PEP','PM','MO','CL','EL',
  'CAT','GE','HON','UPS','BA','RTX','DE','LMT','MMM','ETN',
  'XOM','CVX','COP','SLB','EOG','NFLX','DIS','CMCSA','TMUS','VZ',
  'AMT','PLD','NEE','DUK','SO','LIN','APD')
snapshot <- p('data/source/yahoo_prices.csv')
if (!file.exists(snapshot)) {
  downloads <- lapply(c(tickers, 'SPY'), function(s) {
    message('Downloading ', s)
    z <- tq_get(s, from = '2022-01-01', to = '2026-11-01')
    if (!is.data.frame(z) || nrow(z) == 0) stop('No data for ', s)
    z
  })
  write_csv(bind_rows(downloads), snapshot)
  write_lines(c('Source: Yahoo Finance via tidyquant::tq_get',
    paste('Downloaded UTC:', format(Sys.time(), tz = 'UTC', usetz = TRUE)),
    'Requested from 2022-01-01 through exclusive end 2026-11-01.',
    'Saved vintage is reused. Adjusted prices are vendor-adjusted historical data, not a point-in-time archive.'),
    p('data/source/SOURCE.txt'))
}
prices <- read_csv(snapshot, show_col_types = FALSE) %>% arrange(symbol, date)
stopifnot(!anyDuplicated(prices[c('symbol','date')]),
          setequal(unique(prices$symbol), c(tickers, 'SPY')))
spy <- prices %>% filter(symbol == 'SPY') %>%
  transmute(date, spy_price = adjusted, spy_ret = adjusted / lag(adjusted) - 1)
calendar <- spy$date
# Require full aligned histories to keep lead(20) a common trading horizon.
coverage <- map_dfr(tickers, function(s) {
  z <- filter(prices, symbol == s)
  tibble(symbol = s, rows = nrow(z), missing_dates = sum(!calendar %in% z$date),
    valid_prices = all(is.finite(z$adjusted) & z$adjusted > 0),
    included = identical(z$date, calendar) && all(complete.cases(z)) &&
      all(z$adjusted > 0))
})
save_table(coverage, 'data_coverage.csv')
if (!all(coverage$included)) stop('Incomplete stock histories: inspect data_coverage.csv before proceeding.')

# Exact classroom features, including the reversed older/recent price ratios.
# OHLCV and adjusted price were also predictors in its target ~ . recipe.
# Signals are formed after the close; entry is at the following close.
df <- prices %>% filter(symbol != 'SPY') %>%
  group_by(symbol) %>% mutate(return = adjusted / lag(adjusted) - 1) %>% ungroup() %>%
  left_join(select(spy, date, spy_ret), by = 'date') %>%
  group_by(symbol) %>% mutate(
    mom_1m = lag(adjusted,21) / lag(adjusted,1) - 1,
    mom_3m = lag(adjusted,63) / lag(adjusted,1) - 1,
    mom_6m = lag(adjusted,126) / lag(adjusted,1) - 1,
    vol_1m = slide_dbl(lag(return), sd, .before = 21, .complete = TRUE),
    ret_5d = lag(adjusted,5) / lag(adjusted,1) - 1,
    excess_ret = return - spy_ret,
    entry_date = lead(date,1), exit_date = lead(date,20),
    target = lead(adjusted,20) / lead(adjusted,1) - 1
  ) %>% ungroup() %>% drop_na()
features <- c('open','high','low','close','volume','adjusted','return','spy_ret',
              'mom_1m','mom_3m','mom_6m','vol_1m','ret_5d','excess_ret')
cutoff <- as.Date('2024-01-01')
train <- filter(df, date < cutoff, exit_date < cutoff)
test <- filter(df, date >= cutoff)
stopifnot(max(train$exit_date) < min(test$date),
          all(is.finite(as.matrix(df[,c(features,'target')]))))
save_table(tibble(split = c('Training','Purged at test boundary','Test'),
  observations = c(nrow(train), sum(df$date < cutoff & df$exit_date >= cutoff), nrow(test))),
  'sample_counts.csv')
# Pre-specified regularization attempt: no tuning or model selection on test data.
# min_child_weight is the native equivalent of parsnip's min_n for this engine.
settings <- tibble(model = c('Original XGBoost','Shallow XGBoost'),
  trees = 300L, depth = c(5L,2L), learning_rate = 0.05, min_child_weight = c(10,50))
save_table(settings, 'model_settings.csv')
train_matrix <- xgb.DMatrix(as.matrix(train[,features]), label = train$target)
test_matrix <- xgb.DMatrix(as.matrix(test[,features]))
preds <- test %>% select(symbol, date, entry_date, exit_date, target)
for (i in seq_len(nrow(settings))) {
  set.seed(123)
  fit <- xgb.train(params = list(objective = 'reg:squarederror',
    max_depth = settings$depth[i], eta = 0.05, min_child_weight = settings$min_child_weight[i],
    gamma = 0, subsample = 1, colsample_bytree = 1, lambda = 1, alpha = 0,
    tree_method = 'hist', nthread = 2, seed = 123),
    data = train_matrix, nrounds = 300, verbose = 0)
  preds[[settings$model[i]]] <- as.numeric(predict(fit, test_matrix))
}
preds[['Zero return']] <- 0
save_table(preds, 'test_predictions.csv')
metrics <- map_dfr(c(settings$model,'Zero return'), function(m) tibble(
  model = m, observations = nrow(preds),
  rmse = sqrt(mean((preds[[m]] - preds$target)^2)),
  mae = mean(abs(preds[[m]] - preds$target))))
save_table(metrics, 'prediction_metrics.csv')

# Adjacent 19-interval holding blocks: signal at t, buy at t+1, sell at t+20.
# Next signal is t+19, available before the rebalance at t+20.
# This keeps the original target, without multiplying overlapping forward returns.
first_signal <- match(min(test$date), calendar)
last_signal <- match(max(test$date), calendar)
signals <- calendar[seq(first_signal, last_signal, by = 19)]
holdings <- map_dfr(settings$model, function(m) {
  map_dfr(signals, function(d) {
    z <- preds %>% filter(date == d) %>% arrange(desc(.data[[m]]), symbol) %>% slice_head(n = 10)
    stopifnot(nrow(z) == 10)
    positive <- pmax(z[[m]],0)
    z %>% transmute(model = m, symbol, signal_date = date, entry_date, exit_date,
      prediction = .data[[m]], actual_return = target,
      weight = if (sum(positive) > 0) positive/sum(positive) else rep(0.1,10))
  })
})
save_table(holdings, 'portfolio_holdings.csv')
blocks <- holdings %>% group_by(model, signal_date, entry_date, exit_date) %>%
  summarise(gross_return = sum(weight * actual_return), .groups = 'drop')
spy_blocks <- blocks %>% distinct(signal_date, entry_date, exit_date) %>%
  mutate(model = 'Passive SPY', gross_return =
    spy$spy_price[match(exit_date,spy$date)]/spy$spy_price[match(entry_date,spy$date)]-1)
blocks <- bind_rows(blocks, spy_blocks) %>% arrange(model, entry_date) %>%
  group_by(model) %>% mutate(
    # Conservative sensitivity: full liquidation + repurchase every model block.
    # Passive SPY incurs only an initial buy and final sale, not repeated turnover.
    net_return = if_else(model == 'Passive SPY',
      (1+gross_return) * if_else(row_number()==1,0.999,1) *
        if_else(row_number()==n(),0.999,1) - 1,
      (1+gross_return) * 0.999^2 - 1),
    gross_growth = cumprod(1+gross_return), net_growth = cumprod(1+net_return)) %>% ungroup()
for (m in unique(blocks$model)) {
  z <- filter(blocks, model == m)
  stopifnot(all(head(z$exit_date,-1) == tail(z$entry_date,-1)),
            all(match(z$exit_date,calendar)-match(z$entry_date,calendar) == 19))
}
save_table(blocks, 'portfolio_returns.csv')
performance <- blocks %>% group_by(model) %>% summarise(
  blocks = n(), entry = min(entry_date), exit = max(exit_date),
  cumulative_return = last(gross_growth)-1,
  cost_adjusted_return = last(net_growth)-1,
  annualized_sharpe = mean(gross_return)/sd(gross_return)*sqrt(252/19),
  cost_adjusted_sharpe = mean(net_return)/sd(net_return)*sqrt(252/19), .groups='drop')
save_table(performance, 'investment_metrics.csv')
save_table(tibble(raw_start=min(prices$date), raw_end=max(prices$date), stocks=length(tickers),
  train_signal_start=min(train$date), train_signal_end=max(train$date), train_label_end=max(train$exit_date),
  test_signal_start=min(test$date), test_signal_end=max(test$date),
  test_label_end=max(test$exit_date), training_rows=nrow(train), test_rows=nrow(test)), 'study_window.csv')

cols <- c('Original XGBoost'='#2563A6','Shallow XGBoost'='#D97706','Passive SPY'='#555555','Zero return'='#555555')
growth <- bind_rows(blocks %>% transmute(model,date=exit_date,growth=gross_growth),
  blocks %>% group_by(model) %>% summarise(date=min(entry_date),growth=1,.groups='drop'))
g <- ggplot(growth,aes(date,growth,color=model)) + geom_line(linewidth=0.8) +
  scale_color_manual(values=cols) + scale_y_continuous(labels=scales::label_dollar()) +
  labs(x=NULL,y='Value of $1 (before costs)',color=NULL) + theme_minimal(base_size=12) +
  theme(legend.position='bottom',panel.grid.minor=element_blank())
ggsave(p('results/figures/portfolio_growth.png'),g,width=8,height=4.7,dpi=180)
g2 <- metrics %>% pivot_longer(c(rmse,mae),names_to='metric',values_to='error') %>%
  ggplot(aes(model,error*100,fill=model)) + geom_col(width=.6) + facet_wrap(~toupper(metric)) +
  scale_fill_manual(values=cols) + labs(x=NULL,y='Prediction error (percentage points)') +
  theme_minimal(base_size=11) + theme(legend.position='none',axis.text.x=element_text(angle=15,hjust=1))
ggsave(p('results/figures/prediction_errors.png'),g2,width=8,height=4,dpi=180)
writeLines(capture.output(sessionInfo()),p('results/session-info.txt'))
print(metrics)
print(performance,width=Inf)
message('Saved Blog 9 results. Rendering only reads these saved outputs.')
