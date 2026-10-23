# Functions for the Blog 7 recovery definitions, sensitivity checks, and Plotly chart.

month_gap <- function(from, to) {
  (lubridate::year(to) - lubridate::year(from)) * 12L +
    lubridate::month(to) - lubridate::month(from)
}

calculate_recovery <- function(data) {
  benchmarks <- data |>
    dplyr::group_by(state) |>
    dplyr::summarise(
      benchmark_2019_average = mean(unemployment_rate[lubridate::year(date) == 2019]),
      benchmark_feb2020 = unemployment_rate[date == as.Date("2020-02-01")][1],
      .groups = "drop"
    )

  peak_rows <- data |>
    dplyr::filter(date >= as.Date("2020-03-01"), date <= as.Date("2020-12-01")) |>
    dplyr::group_by(state) |>
    dplyr::arrange(dplyr::desc(unemployment_rate), date, .by_group = TRUE) |>
    dplyr::slice(1) |>
    dplyr::ungroup() |>
    dplyr::select(state, peak_month = date, peak_rate = unemployment_rate)

  definitions <- c("2019_average", "February_2020")
  rows <- list()
  k <- 1L
  for (i in seq_len(nrow(benchmarks))) {
    state_name <- benchmarks$state[i]
    state_data <- data |>
      dplyr::filter(state == state_name) |>
      dplyr::arrange(date)
    peak <- peak_rows |> dplyr::filter(state == state_name)
    for (definition in definitions) {
      threshold <- if (definition == "2019_average") {
        benchmarks$benchmark_2019_average[i]
      } else {
        benchmarks$benchmark_feb2020[i]
      }
      after_peak <- state_data |> dplyr::filter(date > peak$peak_month)
      first <- after_peak |> dplyr::filter(unemployment_rate <= threshold) |> dplyr::slice(1)

      sustained_month <- as.Date(NA)
      if (nrow(after_peak) >= 3L) {
        below <- after_peak$unemployment_rate <= threshold
        run3 <- which(below & dplyr::lead(below, default = FALSE) &
                        dplyr::lead(below, 2, default = FALSE))
        if (length(run3)) sustained_month <- after_peak$date[run3[1]]
      }

      first_month <- if (nrow(first)) first$date[1] else as.Date(NA)
      rows[[k]] <- tibble::tibble(
        state = state_name,
        benchmark = definition,
        benchmark_rate = threshold,
        peak_month = peak$peak_month,
        peak_rate = peak$peak_rate,
        first_return_month = first_month,
        months_peak_to_first_return = if (!is.na(first_month)) month_gap(peak$peak_month, first_month) else NA_integer_,
        sustained_return_month = sustained_month,
        months_peak_to_sustained_return = if (!is.na(sustained_month)) month_gap(peak$peak_month, sustained_month) else NA_integer_,
        reached_by_end = !is.na(first_month),
        sustained_by_end = !is.na(sustained_month)
      )
      k <- k + 1L
    }
  }
  dplyr::bind_rows(rows)
}

calculate_cutoffs <- function(recovery, cutoffs = as.Date(c("2021-12-01", "2022-12-01"))) {
  tidyr::crossing(recovery, cutoff = cutoffs) |>
    dplyr::mutate(
      first_return_observed_by_cutoff = !is.na(first_return_month) & first_return_month <= cutoff,
      sustained_return_observed_by_cutoff = !is.na(sustained_return_month) & sustained_return_month <= cutoff
    ) |>
    dplyr::select(state, benchmark, cutoff, first_return_observed_by_cutoff,
                  sustained_return_observed_by_cutoff)
}

benchmark_rankings <- function(recovery) {
  recovery |>
    dplyr::group_by(benchmark) |>
    dplyr::summarise(
      first_return_order = {
        observed <- which(!is.na(months_peak_to_first_return))
        if (!length(observed)) "Neither state returned by the end of the study" else
          paste0(paste(state[observed[order(months_peak_to_first_return[observed])]], collapse = " then "),
                 if (anyNA(months_peak_to_first_return)) paste0("; no return observed for ", paste(state[is.na(months_peak_to_first_return)], collapse = ", ")) else "")
      },
      sustained_return_order = {
        observed <- which(!is.na(months_peak_to_sustained_return))
        if (!length(observed)) "Neither state sustained a return by the end of the study" else
          paste0(paste(state[observed[order(months_peak_to_sustained_return[observed])]], collapse = " then "),
                 if (anyNA(months_peak_to_sustained_return)) paste0("; not observed for ", paste(state[is.na(months_peak_to_sustained_return)], collapse = ", ")) else "")
      },
      .groups = "drop"
    )
}

calculate_recovery_gaps <- function(data, recovery = calculate_recovery(data)) {
  benchmarks <- recovery |> dplyr::select(state, benchmark, benchmark_rate)
  data |> dplyr::inner_join(benchmarks, by = "state", relationship = "many-to-many") |>
    dplyr::mutate(recovery_gap = unemployment_rate - benchmark_rate)
}

make_recovery_plot <- function(data, recovery) {
  colors <- c(Texas = "#0072B2", California = "#D55E00")
  pale <- c(Texas = "rgba(0,114,178,0.45)", California = "rgba(213,94,0,0.45)")
  labels <- c("2019_average" = "2019 average", "February_2020" = "February 2020")
  gap_data <- calculate_recovery_gaps(data, recovery)
  states <- names(colors)
  state_series <- lapply(states, function(state_name) data |> dplyr::filter(state == state_name) |> dplyr::arrange(date))
  names(state_series) <- states
  plot <- plotly::plot_ly(height = 510)

  # Keep each return marker on its state's 60-point time-series trace. The
  # marker therefore always shares that series' x/y coordinates.
  for (state_name in states) {
    z <- state_series[[state_name]]
    initial <- gap_data |> dplyr::filter(state == state_name, benchmark == "2019_average") |> dplyr::arrange(date)
    result <- recovery |> dplyr::filter(state == state_name, benchmark == "2019_average")
    marker_size <- rep(0, nrow(z))
    point_text <- rep("", nrow(z))
    if (!is.na(result$first_return_month)) {
      i <- match(result$first_return_month, z$date)
      marker_size[i] <- 14
      sustained <- !is.na(result$sustained_return_month) && result$sustained_return_month == result$first_return_month
      point_text[i] <- paste0("First return; three-month check: ", if (sustained) "met" else "not met")
    }
    plot <- plotly::add_trace(plot, x = z$date, y = z$unemployment_rate,
      customdata = cbind(initial$unemployment_rate, initial$benchmark_rate, initial$recovery_gap),
      text = point_text, type = "scatter", mode = "lines+markers", name = state_name, showlegend = TRUE,
      line = list(color = colors[[state_name]], width = 2.5),
      marker = list(color = colors[[state_name]], size = marker_size,
        line = list(color = "white", width = 1.5)),
      hovertemplate = paste0(state_name, "<br>%{x|%B %Y}<br>Unemployment: %{customdata[0]:.1f}%",
        "<br>Selected benchmark: %{customdata[1]:.2f}%",
        "<br>Recovery gap: %{customdata[2]:+.2f} percentage points<br>%{text}<extra></extra>"))
  }

  trace_count <- 2L
  benchmark_indices <- list()
  for (benchmark in names(labels)) {
    benchmark_indices[[benchmark]] <- integer()
    for (state_name in states) {
      item <- recovery |> dplyr::filter(state == state_name, .data$benchmark == .env$benchmark)
      plot <- plotly::add_trace(plot, x = range(data$date), y = rep(item$benchmark_rate, 2),
        type = "scatter", mode = "lines", name = state_name, showlegend = FALSE,
        visible = benchmark == "2019_average",
        line = list(color = pale[[state_name]], width = 1.5, dash = "dash"),
        hovertemplate = paste0(state_name, " benchmark: %{y:.2f}%<extra></extra>"))
      trace_count <- trace_count + 1L
      benchmark_indices[[benchmark]] <- c(benchmark_indices[[benchmark]], trace_count)
    }
  }

  combos <- list(
    list(view = "Unemployment Rate", benchmark = "2019_average", label = "Rate · 2019 average"),
    list(view = "Unemployment Rate", benchmark = "February_2020", label = "Rate · February 2020"),
    list(view = "Recovery Gap", benchmark = "2019_average", label = "Gap · 2019 average"),
    list(view = "Recovery Gap", benchmark = "February_2020", label = "Gap · February 2020")
  )
  buttons <- lapply(combos, function(combo) {
    benchmark <- combo$benchmark
    gap_view <- combo$view == "Recovery Gap"
    state_data <- lapply(states, function(state_name) {
      gap_data |> dplyr::filter(state == state_name, .data$benchmark == .env$benchmark) |> dplyr::arrange(date)
    })
    ys <- lapply(state_data, function(z) if (gap_view) z$recovery_gap else z$unemployment_rate)
    customs <- lapply(state_data, function(z) cbind(z$unemployment_rate, z$benchmark_rate, z$recovery_gap))
    texts <- lapply(seq_along(states), function(i) {
      result <- recovery |> dplyr::filter(state == states[i], .data$benchmark == .env$benchmark)
      z <- state_data[[i]]
      value <- rep("", nrow(z))
      if (!is.na(result$first_return_month)) {
        j <- match(result$first_return_month, z$date)
        sustained <- !is.na(result$sustained_return_month) && result$sustained_return_month == result$first_return_month
        value[j] <- paste0("First return; three-month check: ", if (sustained) "met" else "not met")
      }
      value
    })
    marker_sizes <- lapply(texts, function(z) ifelse(nzchar(z), 14, 0))
    benchmark_y <- unlist(lapply(names(labels), function(b) lapply(states, function(state_name) {
      item <- recovery |> dplyr::filter(state == state_name, .data$benchmark == .env$b)
      rep(item$benchmark_rate, 2)
    })), recursive = FALSE)
    y_all <- unname(c(unname(ys), unname(benchmark_y)))
    custom_all <- unname(c(unname(customs), rep(list(NULL), 4)))
    text_all <- unname(c(unname(texts), rep(list(NULL), 4)))
    size_all <- unname(c(unname(marker_sizes), rep(list(c(0, 0)), 4)))
    visible <- rep(FALSE, trace_count); visible[1:2] <- TRUE
    if (!gap_view) visible[benchmark_indices[[benchmark]]] <- TRUE
    yrange <- if (!gap_view) c(0, ceiling(max(data$unemployment_rate)) + 1) else {
      z <- gap_data |> dplyr::filter(.data$benchmark == .env$benchmark)
      r <- range(z$recovery_gap); c(min(-1, floor(r[1])), max(1, ceiling(r[2])))
    }
    list(label = combo$label, method = "update",
      args = list(
        list(visible = visible, y = y_all, customdata = custom_all, text = text_all,
          `marker.size` = size_all),
        list(yaxis = list(title = if (gap_view) "Unemployment gap (percentage points)" else "Unemployment rate (%)",
          range = yrange,
          tickvals = if (gap_view) pretty(yrange, n = 6) else seq(3, ceiling(max(data$unemployment_rate)) + 1, by = 3),
          ticksuffix = if (gap_view) "" else "%", zeroline = gap_view,
          zerolinecolor = "#666666", zerolinewidth = 2))))
  })

  plot |> plotly::layout(
    paper_bgcolor = "white", plot_bgcolor = "white",
    font = list(family = "Arial, sans-serif", size = 14, color = "#333333"),
    xaxis = list(title = "Month", type = "date", range = range(data$date), tickformat = "%Y", dtick = "M12", ticklabelstandoff = 8, rangeslider = list(visible = FALSE), showgrid = FALSE),
    yaxis = list(title = "Unemployment rate (%)", range = c(0, ceiling(max(data$unemployment_rate)) + 1), tickvals = seq(3, ceiling(max(data$unemployment_rate)) + 1, by = 3), ticksuffix = "%", gridcolor = "#eeeeee"),
    hovermode = "closest",
    legend = list(orientation = "h", x = 0, y = 1.02, itemclick = FALSE, itemdoubleclick = FALSE),
    updatemenus = list(list(type = "dropdown", x = 0, y = 1.14, xanchor = "left", yanchor = "top", active = 0, buttons = buttons)),
    annotations = list(list(x = 0, y = 1.23, xref = "paper", yref = "paper", text = "Chart view and benchmark", showarrow = FALSE, xanchor = "left")),
    margin = list(l = 75, r = 20, t = 115, b = 115)) |>
    plotly::config(displaylogo = FALSE, responsive = TRUE,
      modeBarButtonsToRemove = c("select2d", "lasso2d", "zoomIn2d", "zoomOut2d", "pan2d", "hoverCompareCartesian"))
}
