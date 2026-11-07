# =============================================================================
# 03b_fetch_gdelt.R - OPTIONALE Zusatzquelle: GDELT DOC 2.0 API (weltweite Online-News)
# Nur aktiv mit USE_GDELT=1. GDELT drosselt stark (max. 1 Anfrage / 5 s, geteilte Cloud-IPs
# werden oft ganz blockiert); der Erstabruf dauert lokal ca. 60-90 Minuten.
#
# GDELT liest und klassifiziert täglich Nachrichtenartikel aus über 100 Sprachen.
# Pro Land werden vier tägliche Zeitreihen ab 2017 abgefragt und zu Monaten verdichtet:
#   conflict  Anteil der Weltberichterstattung über das Land mit Thema "bewaffneter Konflikt"
#   unrest    ... mit Thema "Proteste"
#   econ      ... mit Thema Inflation / Wechselkurs
#   tone      durchschnittliche Tonalität aller Artikel über das Land (negativ = schlecht)
# Die API erlaubt höchstens eine Anfrage alle 5 Sekunden -> Ergebnisse werden pro Land
# gecacht und bei späteren Läufen nur noch die letzten Monate nachgeladen.
# =============================================================================

GDELT_THEMES <- list(
  conflict = list(mode = "timelinevol",  theme = "theme:ARMEDCONFLICT"),
  unrest   = list(mode = "timelinevol",  theme = "theme:PROTEST"),
  econ     = list(mode = "timelinevol",  theme = "(theme:ECON_INFLATION OR theme:ECON_CURRENCY_EXCHANGE_RATE)"),
  tone     = list(mode = "timelinetone", theme = "")
)

# Suchbegriffe pro Land: World-Bank-Name bereinigt, Sonderfälle von Hand
GDELT_NAME_OVERRIDES <- c(
  COD = '("DR Congo" OR "Democratic Republic of Congo" OR "Democratic Republic of the Congo")',
  COG = '("Republic of Congo" OR "Brazzaville")', CIV = '("Ivory Coast" OR "Cote d\'Ivoire")',
  KOR = '"South Korea"', PRK = '"North Korea"', LAO = '"Laos"', SYR = '"Syria"', RUS = '"Russia"',
  TUR = '("Turkey" OR "Turkiye")', CZE = '("Czech Republic" OR "Czechia")', MMR = '("Myanmar" OR "Burma")',
  SWZ = '"Eswatini"', VNM = '"Vietnam"', KGZ = '"Kyrgyzstan"', SVK = '"Slovakia"', MKD = '"North Macedonia"',
  GEO = '("Tbilisi" OR "Georgian government")', GIN = '("Conakry" OR "Guinean")', GMB = '"Gambia"',
  USA = '"United States"', GBR = '"United Kingdom"', ARE = '"United Arab Emirates"', IRN = '"Iran"',
  EGY = '"Egypt"', YEM = '"Yemen"', VEN = '"Venezuela"', HKG = NA, PRI = NA, PSE = NA)

gdelt_query_term <- function(iso3c, name) {
  ov <- GDELT_NAME_OVERRIDES[iso3c]
  if (!is.na(names(ov)) && !is.na(ov)) return(unname(ov))
  if (!is.na(names(ov)) && is.na(ov)) return(NA_character_)
  sprintf('"%s"', str_trim(sub(",.*$", "", name)))
}

.gdelt_last <- 0
gdelt_get <- function(query, mode, start, end = Sys.Date()) {
  url <- paste0("https://api.gdeltproject.org/api/v2/doc/doc?format=json&mode=", mode,
                "&query=", URLencode(query, reserved = TRUE),
                "&startdatetime=", format(start, "%Y%m%d000000"),
                "&enddatetime=", format(end, "%Y%m%d235959"))
  for (attempt in 1:8) {
    wait <- CFG$gdelt_wait - as.numeric(Sys.time()) + .gdelt_last
    if (wait > 0) Sys.sleep(wait)
    .gdelt_last <<- as.numeric(Sys.time())
    txt <- tryCatch(paste(readLines(url(url, headers = c(`User-Agent` = "global-risk-early-warning (R)")),
                                    warn = FALSE), collapse = ""), error = function(e) "")
    if (startsWith(txt, "{")) {
      js <- fromJSON(txt)
      if (is.null(js$timeline) || !length(js$timeline$data)) return(tibble(date = as.Date(character()), value = numeric()))
      d <- js$timeline$data[[1]]
      return(tibble(date = as.Date(substr(d$date, 1, 8), "%Y%m%d"), value = as.numeric(d$value)))
    }
    if (grepl("limit requests", txt) || txt == "") {        # Rate-Limit / Netzwerk: exponentiell warten
      Sys.sleep(min(15 * 2^(attempt - 1), 300)); next
    }
    warning("GDELT-Anfrage abgelehnt (", substr(txt, 1, 80), "): ", query); return(NULL)
  }
  warning("GDELT: Rate-Limit nicht überwunden für ", query); NULL
}

fetch_gdelt_country <- function(iso3c, term) {
  f <- file.path(DIR$raw, "gdelt", paste0(iso3c, ".rds"))
  old <- if (file.exists(f)) readRDS(f) else NULL
  out <- list()
  for (k in names(GDELT_THEMES)) {
    prev  <- if (!is.null(old)) filter(old, key == k) else NULL
    have  <- !is.null(prev) && nrow(prev) > 0
    if (have && max(prev$date) >= Sys.Date() - 20 && !CFG$refresh) { out[[k]] <- prev; next }
    start <- if (have && !CFG$refresh) max(prev$date) - 60 else CFG$gdelt_start
    q <- str_trim(paste(term, GDELT_THEMES[[k]]$theme))
    new <- gdelt_get(q, GDELT_THEMES[[k]]$mode, start)
    if (is.null(new)) { out[[k]] <- prev; next }
    new <- mutate(new, key = k)
    out[[k]] <- bind_rows(if (have) filter(prev, date < start), new)
  }
  res <- bind_rows(out)
  if (nrow(res)) saveRDS(res, f)
  res
}

f_gdelt <- file.path(DIR$proc, "gdelt_monthly.rds")
if (identical(Sys.getenv("USE_GDELT"), "1")) {
ctry <- readRDS(f_ctry)
ctry$term <- map2_chr(ctry$iso3c, ctry$country, gdelt_query_term)
todo <- filter(ctry, !is.na(term))
log_msg("GDELT: %d Länder x %d Zeitreihen (Abstand %.0fs; Erstabruf dauert ca. %.0f Min.)",
        nrow(todo), length(GDELT_THEMES), CFG$gdelt_wait,
        nrow(todo) * length(GDELT_THEMES) * CFG$gdelt_wait / 60)
gd <- map_dfr(seq_len(nrow(todo)), function(i) {
  d <- fetch_gdelt_country(todo$iso3c[i], todo$term[i])
  if (i %% 10 == 0) log_msg("  GDELT %d/%d Länder", i, nrow(todo))
  if (nrow(d)) mutate(d, iso3c = todo$iso3c[i]) else NULL
})
gdelt_monthly <- gd |>
  mutate(month = month_floor(date)) |>
  group_by(iso3c, key, month) |> summarise(value = mean(value, na.rm = TRUE), days = n(), .groups = "drop") |>
  filter(month < month_floor(Sys.Date()) | days >= 20)            # unvollständigen laufenden Monat weglassen
saveRDS(gdelt_monthly, f_gdelt)
log_msg("GDELT: %d Länder mit Daten, bis %s", n_distinct(gdelt_monthly$iso3c), format(max(gdelt_monthly$month), "%Y-%m"))
} else log_msg("GDELT übersprungen (aktivieren mit USE_GDELT=1)")
