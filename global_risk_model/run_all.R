#!/usr/bin/env Rscript
# =============================================================================
# Global Risk Model - komplette Pipeline
#   Rscript run_all.R            (verwendet Caches in data/)
#   RISK_REFRESH=1 Rscript run_all.R   (alle Daten neu laden)
# =============================================================================
args <- commandArgs(trailingOnly = FALSE)
f <- sub("^--file=", "", args[grep("^--file=", args)])
if (length(f)) setwd(dirname(normalizePath(f)))

t_start <- Sys.time()
for (s in c("00_config", "01_fetch_worldbank", "02_fetch_ungdc", "03_text_features",
            "04_build_panel", "05_models", "06_evaluation", "07_report")) {
  cat("\n==== ", s, " ====\n", sep = "")
  source(file.path("R", paste0(s, ".R")), local = FALSE, encoding = "UTF-8")
}
log_msg("Fertig in %.1f Minuten.", as.numeric(difftime(Sys.time(), t_start, units = "mins")))
