# Run from the website-recovered project root:
# Rscript blog/posts/post7/code/run_analysis.R

post_dir <- if (dir.exists("blog/posts/post7/data/source")) "blog/posts/post7" else "."
source(file.path(post_dir, "code", "analysis.R"))
data <- readr::read_csv(file.path(post_dir, "data", "source", "unemployment_tx_ca.csv"),
                        show_col_types = FALSE)

recovery <- calculate_recovery(data)
cutoffs <- calculate_cutoffs(recovery)
rankings <- benchmark_rankings(recovery)

out <- file.path(post_dir, "results")
table_dir <- file.path(out, "tables")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
readr::write_csv(recovery, file.path(table_dir, "recovery_summary.csv"))
gaps <- calculate_recovery_gaps(data, recovery)
readr::write_csv(gaps |> dplyr::select(date, state, benchmark, benchmark_rate, unemployment_rate, recovery_gap), file.path(table_dir, "recovery_gaps.csv"))
readr::write_csv(cutoffs, file.path(table_dir, "earlier_cutoff_check.csv"))
readr::write_csv(rankings, file.path(table_dir, "benchmark_rankings.csv"))

cat("Recovery results by state and benchmark:\n")
print(recovery, n = Inf)
cat("\nEarlier fixed cutoff checks:\n")
print(cutoffs, n = Inf)
cat("\nBenchmark rankings:\n")
print(rankings, n = Inf)

# Build and save a copy for checking the widget outside the QMD.
widget <- make_recovery_plot(data, recovery)
htmlwidgets::saveWidget(widget, file.path(out, "interactive_recovery.html"),
                        selfcontained = FALSE)
cat("\nSaved aggregate tables under ", table_dir,
    " and interactive chart under ", out, ".\n", sep = "")
