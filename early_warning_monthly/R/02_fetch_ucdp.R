# =============================================================================
# 02_fetch_ucdp.R - Monatliche Konfliktdaten: UCDP Georeferenced Event Dataset
#   * GED (jährlich, geprüft) + GED Candidate (monatlich, vorläufig, ~1 Monat Verzug)
#   * Downloads von https://ucdp.uu.se/downloads/ (frei, ohne API-Token)
# =============================================================================
f_ucdp <- file.path(DIR$proc, "ucdp_monthly.rds")

if (!file.exists(f_ucdp) || CFG$refresh) {
  page  <- paste(readLines("https://ucdp.uu.se/downloads/", warn = FALSE), collapse = " ")
  links <- unique(str_extract_all(page, "https://ucdp\\.uu\\.se/downloads/[^\"' ]+")[[1]])
  ged_url  <- sort(grep("/ged/ged\\d+-csv\\.zip$", links, value = TRUE), decreasing = TRUE)[1]
  cand_url <- sort(grep("/candidateged/GEDEvent_v\\d+_\\d+_\\d+_\\d+\\.csv$", links, value = TRUE), decreasing = TRUE)[1]
  if (is.na(ged_url)) stop("GED-Download-Link nicht gefunden.")
  log_msg("UCDP: %s + %s", basename(ged_url), ifelse(is.na(cand_url), "(kein Candidate)", basename(cand_url)))

  cols <- c("type_of_violence", "country_id", "date_start", "best")
  dl <- function(u) { f <- file.path(DIR$raw, basename(u)); if (!file.exists(f) || CFG$refresh) download.file(u, f, mode = "wb", quiet = TRUE); f }
  read_ged <- function(f) {
    if (grepl("\\.zip$", f)) { ex <- file.path(DIR$raw, "ged"); unzip(f, exdir = ex)
      f <- list.files(ex, pattern = "\\.csv$", full.names = TRUE)[1] }
    read_csv(f, col_select = all_of(cols), show_col_types = FALSE, progress = FALSE)
  }
  ged <- read_ged(dl(ged_url)) |> mutate(src = "ged")
  if (!is.na(cand_url)) {
    cand <- read_ged(dl(cand_url)) |> mutate(src = "candidate")
    ged  <- bind_rows(ged, filter(cand, as.Date(date_start) > max(as.Date(ged$date_start))))
  }
  ucdp <- ged |>
    mutate(month = month_floor(as.Date(date_start)),
           iso3c = countrycode(country_id, "gwn", "iso3c", custom_match = c(`340` = "SRB", `345` = "SRB", `347` = "XKX",
                                                                          `678` = "YEM", `626` = "SSD", `816` = "VNM"))) |>
    filter(!is.na(iso3c), month >= CFG$start_month - 365) |>
    group_by(iso3c, month) |>
    summarise(deaths = sum(best), deaths_sb = sum(best[type_of_violence == 1]),
              deaths_ns = sum(best[type_of_violence == 2]), deaths_os = sum(best[type_of_violence == 3]),
              events = n(), .groups = "drop")
  attr(ucdp, "last_month") <- max(month_floor(as.Date(ged$date_start)))
  saveRDS(ucdp, f_ucdp)
  log_msg("UCDP: %d Länder-Monate mit Gewalt, Daten bis %s", nrow(ucdp), format(attr(ucdp, "last_month"), "%Y-%m"))
} else log_msg("UCDP aus Cache")
