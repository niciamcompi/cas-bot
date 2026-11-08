# =============================================================================
# 04b_foundation.R - Zeitreihen-Foundation-Modelle (zero-shot): TimesFM 3, Chronos-2, Moirai-2
#
# Die Modelle sagen Zahlenreihen vorher, keine Ja/Nein-Ereignisse. Deshalb:
#   Konflikt: Reihe log1p(Tote der letzten 3 Monate) -> Quantilprognose für t+3
#             -> P(Tote in t+1..t+3 >= 25)
#   Währung:  Reihe log(Wechselkurs) -> Quantilprognose für t+3 -> P(Abwertung >= 15 %)
# Die Rechnung läuft in Python (py/foundation_forecasts.py). Ergebnisse werden gecacht und nur neu
# berechnet, wenn sich die Eingabereihen ändern. Ohne Python-Umgebung wird der Schritt übersprungen.
#   USE_FM=0         Foundation-Modelle abschalten
#   FM_PYTHON=pfad   eigener Python-Interpreter (sonst .venv im Projektordner)
# =============================================================================
P <- readRDS(file.path(DIR$proc, "panel.rds"))
P$FM_C <- character(0); P$FM_X <- character(0)

fm_python <- function() {
  cand <- c(Sys.getenv("FM_PYTHON"), ".venv/bin/python", ".venv/Scripts/python.exe")
  cand <- cand[nzchar(cand) & file.exists(cand)]
  if (!length(cand)) return(NA_character_)
  # absoluter Pfad OHNE Symlinks aufzulösen (sonst verliert man die virtuelle Umgebung)
  if (grepl("^(/|[A-Za-z]:)", cand[1])) cand[1] else file.path(getwd(), cand[1])
}
py <- fm_python()
f_fm_in  <- file.path(DIR$proc, "fm_series.csv")
f_fm_out <- file.path(DIR$proc, "fm_forecasts.csv")
f_fm_md5 <- file.path(DIR$proc, "fm_series.md5")

if (identical(Sys.getenv("USE_FM"), "0")) {
  log_msg("Foundation-Modelle abgeschaltet (USE_FM=0)")
} else if (is.na(py)) {
  log_msg("Foundation-Modelle übersprungen: keine Python-Umgebung gefunden (siehe README, Abschnitt Foundation-Modelle)")
} else {
  series <- bind_rows(
    P$panel |> transmute(target = "conflict", iso3c, month, value = log1p(deaths3), threshold = log1p(CFG$conflict_thr)),
    P$panel |> transmute(target = "fx", iso3c, month, value = log(fx), threshold = log(1 + CFG$fx_thr))) |>
    filter(month <= P$last_ucdp) |>
    mutate(month = format(month, "%Y-%m-%d"))
  write.csv(series, f_fm_in, row.names = FALSE)
  md5 <- unname(tools::md5sum(f_fm_in))
  cached <- file.exists(f_fm_out) && file.exists(f_fm_md5) && identical(readLines(f_fm_md5), md5) && !CFG$refresh
  if (!cached) {
    log_msg("Foundation-Modelle: starte %s (Erstlauf lädt ca. 1.8 GB Modellgewichte von Hugging Face)", py)
    t0 <- Sys.time()
    st <- system2(shQuote(py), c("py/foundation_forecasts.py", "--start", format(CFG$train_start - 31, "%Y-%m-01"),
                        "--input", f_fm_in, "--output", f_fm_out))
    if (st != 0 || !file.exists(f_fm_out)) {
      warning("Foundation-Modelle fehlgeschlagen (Exit-Code ", st, ") - Pipeline läuft ohne sie weiter.")
    } else {
      writeLines(md5, f_fm_md5)
      log_msg("Foundation-Modelle fertig in %.1f Minuten", as.numeric(difftime(Sys.time(), t0, units = "mins")))
    }
  } else log_msg("Foundation-Prognosen aus Cache")

  if (file.exists(f_fm_out)) {
    fm <- read_csv(f_fm_out, show_col_types = FALSE) |>
      mutate(month = as.Date(month), col = paste0(ifelse(target == "conflict", "fmc_", "fmx_"), model))
    fm_w <- fm |> select(iso3c, month, col, p) |> pivot_wider(names_from = col, values_from = p)
    P$panel <- P$panel |> select(-any_of(setdiff(names(fm_w), c("iso3c", "month")))) |>
      left_join(fm_w, by = c("iso3c", "month"))
    P$FM_C <- grep("^fmc_", names(fm_w), value = TRUE)
    P$FM_X <- grep("^fmx_", names(fm_w), value = TRUE)
    log_msg("Foundation-Features: %s", paste(c(P$FM_C, P$FM_X), collapse = ", "))
  }
}
saveRDS(P, file.path(DIR$proc, "panel.rds"))
