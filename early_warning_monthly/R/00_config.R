# =============================================================================
# 00_config.R - Pakete, Parameter, Hilfsfunktionen
# =============================================================================
suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(purrr); library(stringr); library(readr)
  library(jsonlite); library(ggplot2); library(patchwork); library(countrycode)
  library(glmnet); library(ranger); library(gbm); library(pROC)
})
options(timeout = 3600, dplyr.summarise.inform = FALSE, warn = 1)
invisible(Sys.setlocale("LC_TIME", "C"))   # Datumsformate unabhängig von der Systemsprache
set.seed(42)

CFG <- list(
  start_month   = as.Date("2010-01-01"),  # Beginn Konflikt-/Makrodaten
  gdelt_start   = as.Date("2017-01-01"),  # GDELT-DOC-API reicht bis 2017 zurück
  train_start   = as.Date("2018-01-01"),  # erster Monat mit 12-Monats-Nachrichtenbasis
  test_start    = as.Date("2021-01-01"),  # erster Out-of-sample-Monat
  horizon       = 3,                      # Vorhersagehorizont in Monaten (t+1 ... t+3)
  refit_every   = 6,                      # Modelle alle 6 Monate neu trainieren
  min_pop       = 1e6,                    # nur Länder mit >= 1 Mio. Einwohnern
  conflict_thr  = 25,                     # Todesopfer in 3 Monaten
  fx_thr        = 0.15,                   # Abwertung ggü. USD in 3 Monaten
  watch_k       = 20,                     # Länge der Beobachtungsliste
  n_boot        = 200,
  gdelt_wait    = as.numeric(Sys.getenv("GDELT_WAIT", "6")),   # Sekunden zwischen API-Anfragen
  threads       = max(1L, parallel::detectCores()),
  refresh       = identical(Sys.getenv("RISK_REFRESH"), "1")
)
DIR <- list(raw = "data/raw", proc = "data/processed", out = "output", fig = "output/figures")
invisible(lapply(DIR, dir.create, recursive = TRUE, showWarnings = FALSE))
dir.create(file.path(DIR$raw, "gdelt"), showWarnings = FALSE)

log_msg <- function(...) cat(format(Sys.time(), "[%H:%M:%S] "), sprintf(...), "\n", sep = "")
month_floor <- function(d) as.Date(format(as.Date(d), "%Y-%m-01"))
add_months  <- function(d, k) seq(d, by = paste(k, "months"), length.out = 2)[2]
mi <- function(d) as.integer(format(d, "%Y")) * 12L + as.integer(format(d, "%m")) - 1L   # Monatsindex
clamp <- function(x, lo, hi) pmin(pmax(x, lo), hi)
slog  <- function(x) sign(x) * log1p(abs(x))
locf_limited <- function(x, max_gap = 3) {
  last <- NA_real_; gap <- Inf
  for (i in seq_along(x)) {
    if (!is.na(x[i])) { last <- x[i]; gap <- 0 } else { gap <- gap + 1; if (gap <= max_gap) x[i] <- last }
  }
  x
}
roll_sum <- function(x, k) as.numeric(stats::filter(x, rep(1, k), sides = 1))
lagk <- function(x, k) dplyr::lag(x, k)

PAL <- c(blue = "#2a78d6", orange = "#eb6834", aqua = "#1baf7a", yellow = "#eda100",
         magenta = "#e87ba4", green = "#008300", violet = "#6250d6", red = "#e34948")
INK <- list(primary = "#0b0b0b", secondary = "#52514e", grid = "#e6e5e0", surface = "#fcfcfb")
theme_risk <- function(base = 11) {
  theme_minimal(base_size = base) +
    theme(plot.background = element_rect(fill = INK$surface, colour = NA),
          panel.grid.major = element_line(colour = INK$grid, linewidth = 0.3),
          panel.grid.minor = element_blank(),
          axis.text = element_text(colour = INK$secondary), axis.title = element_text(colour = INK$secondary),
          plot.title = element_text(colour = INK$primary, face = "bold"),
          plot.subtitle = element_text(colour = INK$secondary),
          plot.caption = element_text(colour = INK$secondary, size = rel(0.8)),
          legend.position = "top", legend.title = element_blank(),
          strip.text = element_text(colour = INK$primary, face = "bold"))
}
save_fig <- function(p, name, w = 9, h = 5.5)
  ggsave(file.path(DIR$fig, name), p, width = w, height = h, dpi = 150, bg = INK$surface)
