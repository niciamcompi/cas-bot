# =============================================================================
# 02_fetch_ucdp.R - Monatliche Konfliktdaten: UCDP Georeferenced Event Dataset
#   * GED (jährlich, geprüft) + GED Candidate (monatlich, vorläufig, ~1 Monat Verzug)
#   * Downloads von https://ucdp.uu.se/downloads/ (frei, ohne API-Token)
#   * Räumliche Features aus den Ereignis-Koordinaten:
#       - Ausbreitung: aktive / neue Gewaltzonen (0.5-Grad-Raster) im Land
#       - Nachbarschaft: Tote in ANDEREN Ländern im Umkreis von 500 km um die Städte des Landes
# =============================================================================
f_ucdp <- file.path(DIR$proc, "ucdp_monthly.rds")

if (!file.exists(f_ucdp) || CFG$refresh) {
  page  <- paste(readLines("https://ucdp.uu.se/downloads/", warn = FALSE), collapse = " ")
  links <- unique(str_extract_all(page, "https://ucdp\\.uu\\.se/downloads/[^\"' ]+")[[1]])
  ged_url  <- sort(grep("/ged/ged\\d+-csv\\.zip$", links, value = TRUE), decreasing = TRUE)[1]
  cand_url <- sort(grep("/candidateged/GEDEvent_v\\d+_\\d+_\\d+_\\d+\\.csv$", links, value = TRUE), decreasing = TRUE)[1]
  if (is.na(ged_url)) stop("GED-Download-Link nicht gefunden.")
  log_msg("UCDP: %s + %s", basename(ged_url), ifelse(is.na(cand_url), "(kein Candidate)", basename(cand_url)))

  cols <- c("type_of_violence", "country_id", "date_start", "best", "latitude", "longitude")
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
  gw_iso <- c(`340` = "SRB", `345` = "SRB", `347` = "XKX", `678` = "YEM", `626` = "SSD", `816` = "VNM")
  ged <- ged |>
    mutate(month = month_floor(as.Date(date_start)),
           iso3c = countrycode(country_id, "gwn", "iso3c", custom_match = gw_iso),
           cell  = paste(floor(latitude * 2), floor(longitude * 2)),            # 0.5-Grad-Rasterzelle
           cell_lat = (floor(latitude * 2) + 0.5) / 2, cell_lon = (floor(longitude * 2) + 0.5) / 2) |>
    filter(!is.na(iso3c), month >= CFG$start_month - 365)
  ucdp <- ged |>
    group_by(iso3c, month) |>
    summarise(deaths = sum(best), deaths_sb = sum(best[type_of_violence == 1]),
              deaths_ns = sum(best[type_of_violence == 2]), deaths_os = sum(best[type_of_violence == 3]),
              events = n(), .groups = "drop")

  # --- Ausbreitung: aktive Zellen in den letzten 3 Monaten und davon neue (nicht aktiv in den 12 Monaten davor)
  cm <- distinct(ged, iso3c, cell, month) |> mutate(m = mi(month))
  spread <- cm |> group_by(iso3c) |> group_modify(function(d, key) {
    ms <- seq(min(d$m), max(d$m) + 2)
    tibble(m = ms, cells_3 = vapply(ms, \(x) n_distinct(d$cell[d$m > x - 3 & d$m <= x]), 0),
           new_cells_3 = vapply(ms, \(x) { now <- unique(d$cell[d$m > x - 3 & d$m <= x])
             before <- unique(d$cell[d$m > x - 15 & d$m <= x - 3]); sum(!now %in% before) }, 0))
  }) |> ungroup()

  # --- Nachbarschaft: Zellen im Umkreis von 500 km um die grössten Städte (>= 100'000 Einwohner) jedes Landes
  wc <- maps::world.cities |>
    mutate(iso3c = suppressWarnings(countrycode(country.etc, "country.name", "iso3c",
                                                custom_match = c(Kosovo = "XKX", `Serbia and Montenegro` = "SRB")))) |>
    filter(!is.na(iso3c), iso3c %in% readRDS(f_ctry)$iso3c) |>
    group_by(iso3c) |> filter(pop >= 1e5 | capital == 1 | pop == max(pop)) |>
    slice_max(pop, n = 25, with_ties = FALSE) |> ungroup()
  hav <- function(lat1, lon1, lat2, lon2) {            # Distanz in km
    r <- pi / 180; a <- sin((lat2 - lat1) * r / 2)^2 + cos(lat1 * r) * cos(lat2 * r) * sin((lon2 - lon1) * r / 2)^2
    2 * 6371 * asin(pmin(1, sqrt(a)))
  }
  cells <- distinct(ged, cell, cell_lat, cell_lon)
  near <- map_dfr(split(wc, wc$iso3c), function(cty) {
    d <- outer(seq_len(nrow(cells)), seq_len(nrow(cty)),
               \(i, j) hav(cells$cell_lat[i], cells$cell_lon[i], cty$lat[j], cty$long[j]))
    tibble(near_iso = cty$iso3c[1], cell = cells$cell[apply(d, 1, min) <= 500])
  })
  spill <- ged |> select(iso3c, cell, month, best) |>
    inner_join(near, by = "cell", relationship = "many-to-many") |>
    filter(near_iso != iso3c) |>
    group_by(iso3c = near_iso, month) |> summarise(spill_deaths = sum(best), .groups = "drop")

  ucdp <- ucdp |> full_join(spill, by = c("iso3c", "month")) |>
    full_join(spread |> mutate(month = as.Date(sprintf("%d-%02d-01", m %/% 12, m %% 12 + 1))) |> select(-m),
              by = c("iso3c", "month")) |>
    mutate(across(c(deaths, deaths_sb, deaths_ns, deaths_os, events, spill_deaths, cells_3, new_cells_3), \(x) coalesce(x, 0)))
  attr(ucdp, "last_month") <- max(month_floor(as.Date(ged$date_start)))
  saveRDS(ucdp, f_ucdp)
  log_msg("UCDP: %d Länder-Monate mit Gewalt, Daten bis %s", nrow(ucdp), format(attr(ucdp, "last_month"), "%Y-%m"))
} else log_msg("UCDP aus Cache")
