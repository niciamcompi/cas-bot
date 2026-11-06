# =============================================================================
# 00_config.R - Pakete, Pfade, Parameter
# =============================================================================
suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(purrr); library(stringr)
  library(jsonlite); library(Matrix); library(ggplot2); library(patchwork)
  library(glmnet); library(ranger); library(gbm); library(mgcv); library(pROC)
  library(irlba); library(tidytext); library(tokenizers)
})

options(timeout = 1800, dplyr.summarise.inform = FALSE, warn = 1)
set.seed(42)

CFG <- list(
  years           = 1990:2025,  # Abrufzeitraum
  first_test_year = 2010,       # erstes Out-of-sample-Jahr (Features t -> Ereignis t+1)
  lsa_fit_until   = 2009,       # Text-LSA nur auf Reden <= diesem Jahr fitten (kein Leakage)
  lsa_k           = 15,         # Anzahl latenter Text-Dimensionen
  n_boot          = 300,        # Cluster-Bootstrap-Replikationen (nach Land)
  locf_max        = 3,          # max. Jahre "last observation carried forward"
  threads         = max(1L, parallel::detectCores() - 0L),
  refresh         = identical(Sys.getenv("RISK_REFRESH"), "1"),
  ungdc_doi       = "doi:10.7910/DVN/0TJX8Y"
)

DIR <- list(
  raw  = "data/raw",
  proc = "data/processed",
  out  = "output",
  fig  = "output/figures"
)
invisible(lapply(DIR, dir.create, recursive = TRUE, showWarnings = FALSE))

log_msg <- function(...) cat(format(Sys.time(), "[%H:%M:%S] "), sprintf(...), "\n", sep = "")

# Palette (validierte kategoriale Reihenfolge, siehe README)
PAL <- c(blue = "#2a78d6", orange = "#eb6834", aqua = "#1baf7a", yellow = "#eda100",
         magenta = "#e87ba4", green = "#008300", violet = "#6250d6", red = "#e34948")
INK <- list(primary = "#0b0b0b", secondary = "#52514e", grid = "#e6e5e0", surface = "#fcfcfb")

theme_risk <- function(base = 11) {
  theme_minimal(base_size = base) +
    theme(
      plot.background  = element_rect(fill = INK$surface, colour = NA),
      panel.grid.major = element_line(colour = INK$grid, linewidth = 0.3),
      panel.grid.minor = element_blank(),
      axis.text        = element_text(colour = INK$secondary),
      axis.title       = element_text(colour = INK$secondary),
      plot.title       = element_text(colour = INK$primary, face = "bold"),
      plot.subtitle    = element_text(colour = INK$secondary),
      plot.caption     = element_text(colour = INK$secondary, size = rel(0.8)),
      legend.position  = "top", legend.title = element_blank(),
      strip.text       = element_text(colour = INK$primary, face = "bold")
    )
}
save_fig <- function(p, name, w = 9, h = 5.5) {
  ggsave(file.path(DIR$fig, name), p, width = w, height = h, dpi = 150, bg = INK$surface)
}
