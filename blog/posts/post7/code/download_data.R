# Download and validate the FRED unemployment series for the Blog 7 draft.
# The API key is read from the local environment and is never printed or saved.

required <- c("fredr", "dplyr", "readr", "lubridate", "tibble")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) stop("Install required R packages: ", paste(missing, collapse = ", "))

key <- Sys.getenv("FRED_API_KEY")
if (!nzchar(key)) {
  stop("FRED_API_KEY is not set in this R environment. Set it locally; do not paste it into the script or chat.")
}
fredr::fredr_set_key(key)
rm(key)

series <- c(Texas = "TXUR", California = "CAUR")
start_date <- as.Date("2019-01-01")
end_date <- as.Date("2023-12-31")

metadata <- dplyr::bind_rows(lapply(names(series), function(state_name) {
  id <- unname(series[[state_name]])
  info <- fredr::fredr_series(series_id = id)
  if (nrow(info) != 1L) stop("Could not verify FRED metadata for ", id)
  row <- info[1, ]
  if (!identical(as.character(row$frequency), "Monthly") ||
      !identical(as.character(row$units), "Percent") ||
      !grepl("Seasonally Adjusted", as.character(row$seasonal_adjustment), fixed = TRUE)) {
    stop("Unexpected frequency, units, or seasonal adjustment for ", id)
  }
  tibble::tibble(
    state = state_name,
    series_id = id,
    title = as.character(row$title),
    frequency = as.character(row$frequency),
    units = as.character(row$units),
    seasonal_adjustment = as.character(row$seasonal_adjustment),
    source = "U.S. Bureau of Labor Statistics via FRED",
    accessed_on = as.character(Sys.Date())
  )
}))

observations <- dplyr::bind_rows(lapply(names(series), function(state_name) {
  id <- unname(series[[state_name]])
  x <- fredr::fredr_series_observations(
    series_id = id,
    observation_start = start_date,
    observation_end = end_date,
    sort_order = "asc"
  )
  tibble::tibble(
    date = as.Date(x$date),
    state = state_name,
    unemployment_rate = as.numeric(x$value)
  )
})) |>
  dplyr::arrange(state, date)

expected_dates <- seq(start_date, end_date, by = "month")
if (nrow(observations) != 120L || anyNA(observations$unemployment_rate) ||
    anyDuplicated(observations[c("state", "date")]) ||
    !all(vapply(split(observations$date, observations$state),
                function(x) identical(x, expected_dates), logical(1))) ||
    !is.numeric(observations$unemployment_rate)) {
  stop("Data validation failed: expected 60 complete, unique monthly observations per state.")
}

post_dir <- if (dir.exists("blog/posts/post7/data/source")) "blog/posts/post7" else "."
out_dir <- file.path(post_dir, "data", "source")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
readr::write_csv(observations, file.path(out_dir, "unemployment_tx_ca.csv"))
readr::write_csv(metadata, file.path(out_dir, "series_metadata.csv"))
message("Saved 120 validated observations and series metadata. FRED key was not saved.")
