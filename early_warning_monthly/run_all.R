#!/usr/bin/env Rscript
# =============================================================================
# Monatliches Frühwarnsystem - komplette Pipeline
#   Rscript run_all.R                   (Caches in data/ verwenden)
#   RISK_REFRESH=1 Rscript run_all.R    (alles neu laden und neu rechnen)
# =============================================================================
# Projektordner finden - funktioniert mit Rscript, source() und RStudio ("Source"-Knopf)
proj_dir <- local({
  f <- sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
  if (!length(f)) f <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (!length(f) && requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable())
    f <- tryCatch(rstudioapi::getSourceEditorContext()$path, error = function(e) NULL)
  if (length(f) && nzchar(f[1])) dirname(normalizePath(f[1])) else getwd()
})
setwd(proj_dir)
if (!file.exists("R/02_fetch_ucdp.R"))
  stop("Falscher Arbeitsordner: ", getwd(), "\nBitte zuerst setwd(\".../early_warning_monthly\") ausführen ",
       "oder run_all.R in RStudio öffnen und auf 'Source' klicken.")
cat("Projektordner:", getwd(), "\n")

t_start <- Sys.time()
for (s in c("00_config", "01_fetch_worldbank", "02_fetch_ucdp", "03_fetch_news", "03b_fetch_gdelt", "04_build_panel", "04b_foundation",
            "05_models", "06_evaluation", "07_report")) {
  cat("\n==== ", s, " ====\n", sep = "")
  source(file.path("R", paste0(s, ".R")), encoding = "UTF-8")
}
log_msg("Fertig in %.1f Minuten.", as.numeric(difftime(Sys.time(), t_start, units = "mins")))
