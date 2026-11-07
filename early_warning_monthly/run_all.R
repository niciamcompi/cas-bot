#!/usr/bin/env Rscript
# =============================================================================
# Monatliches Frühwarnsystem - komplette Pipeline
#   Rscript run_all.R                   (Caches in data/ verwenden)
#   RISK_REFRESH=1 Rscript run_all.R    (alles neu laden und neu rechnen)
# =============================================================================
args <- commandArgs(trailingOnly = FALSE)
f <- sub("^--file=", "", args[grep("^--file=", args)])
if (length(f)) setwd(dirname(normalizePath(f)))
t_start <- Sys.time()
for (s in c("00_config", "01_fetch_worldbank", "02_fetch_ucdp", "03_fetch_news", "03b_fetch_gdelt", "04_build_panel",
            "05_models", "06_evaluation", "07_report")) {
  cat("\n==== ", s, " ====\n", sep = "")
  source(file.path("R", paste0(s, ".R")), encoding = "UTF-8")
}
log_msg("Fertig in %.1f Minuten.", as.numeric(difftime(Sys.time(), t_start, units = "mins")))
