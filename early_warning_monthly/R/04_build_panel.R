# =============================================================================
# 04_build_panel.R - Länder-Monats-Panel, Zielvariablen, Features
#
# Zwei Frühwarn-Ziele, jeweils für die nächsten 3 Monate (t+1 ... t+3):
#   y_conflict  >= 25 Todesopfer organisierter Gewalt (UCDP: staatlich, nichtstaatlich, einseitig)
#   y_fx        Währungskrise: Abwertung ggü. USD >= 15 %
# "Ausbruch" (onset) = Land war in den 12 Monaten davor ruhig (unter der jeweiligen Schwelle).
# Alle Features stammen aus Monat t oder früher.
# =============================================================================
ctry  <- readRDS(f_ctry); ucdp <- readRDS(f_ucdp); gem <- readRDS(f_gem); ann <- readRDS(f_ann)
news  <- readRDS(f_news)
gdelt <- if (file.exists(f_gdelt) && identical(Sys.getenv("USE_GDELT"), "1")) readRDS(f_gdelt) else NULL
last_ucdp <- attr(ucdp, "last_month")
months <- seq(CFG$start_month - 365, last_ucdp, by = "month") |> month_floor() |> unique()
log_msg("Panel: %d Länder, %s bis %s", nrow(ctry), format(min(months), "%Y-%m"), format(last_ucdp, "%Y-%m"))

rz <- function(x, k = 12, min_n = 6) {        # z-Wert ggü. den k Vormonaten
  m <- zoo::rollapplyr(lag(x), k, function(v) if (sum(!is.na(v)) >= min_n) mean(v, na.rm = TRUE) else NA, fill = NA, partial = TRUE)
  s <- zoo::rollapplyr(lag(x), k, function(v) if (sum(!is.na(v)) >= min_n) sd(v, na.rm = TRUE) else NA, fill = NA, partial = TRUE)
  (x - m) / pmax(s, 0.05)
}
chg <- function(x, k) 100 * (log(x) - log(lag(x, k)))

gem_w <- gem |> filter(iso3c %in% ctry$iso3c) |>
  pivot_wider(names_from = var, values_from = value, values_fn = mean)
ann_w <- ann |> filter(iso3c %in% ctry$iso3c) |>
  pivot_wider(names_from = var, values_from = value, values_fn = mean) |>
  complete(iso3c, year = full_seq(c(year, as.integer(format(last_ucdp, "%Y"))), 1)) |>
  arrange(iso3c, year) |> group_by(iso3c) |>
  mutate(across(-year, \(x) locf_limited(x, 3))) |> ungroup()
news_w <- news |> rename_with(\(x) paste0("w_", x), -c(iso3c, month))
gd_w <- if (!is.null(gdelt)) gdelt |> select(iso3c, month, key, value) |>
  pivot_wider(names_from = key, values_from = value, names_prefix = "g_") else tibble(iso3c = character(), month = as.Date(character()))
news_last <- month_floor(attr(news, "last_date"))

panel <- expand_grid(iso3c = ctry$iso3c, month = months) |>
  left_join(select(ctry, iso3c, country, region), by = "iso3c") |>
  left_join(ucdp, by = c("iso3c", "month")) |>
  mutate(across(c(deaths, deaths_sb, deaths_ns, deaths_os, events), \(x) coalesce(x, 0))) |>
  left_join(gem_w, by = c("iso3c", "month")) |>
  mutate(year_lag = as.integer(format(month, "%Y")) - 1L) |>
  left_join(ann_w, by = c("iso3c", "year_lag" = "year")) |>
  left_join(news_w, by = c("iso3c", "month")) |>
  left_join(gd_w, by = c("iso3c", "month")) |>
  # Kein Eintrag im Nachrichtenticker = 0 Meldungen (ab Beginn der Textdaten)
  mutate(across(starts_with("w_"), \(x) ifelse(month >= CFG$gdelt_start & month <= news_last, coalesce(x, 0), NA))) |>
  arrange(iso3c, month) |>
  group_by(iso3c) |>
  mutate(
    # ---------- Zielvariablen ----------
    deaths3     = roll_sum(deaths, 3),
    deaths12    = roll_sum(deaths, 12),
    fut_deaths  = lead(deaths3, CFG$horizon),
    y_conflict  = as.numeric(fut_deaths >= CFG$conflict_thr),
    quiet       = coalesce(deaths12 < CFG$conflict_thr, FALSE),
    fx_dep3     = fx / lag(fx, 3) - 1,
    y_fx        = as.numeric(lead(fx, CFG$horizon) / fx - 1 >= CFG$fx_thr),
    fx_quiet    = coalesce(zoo::rollapplyr(fx_dep3, 12, \(v) if (all(is.na(v))) NA else max(v, na.rm = TRUE),
                                           fill = NA, partial = TRUE) < CFG$fx_thr, TRUE),
    # ---------- Konfliktgeschichte ----------
    c_deaths_1  = log1p(deaths),
    c_deaths_3  = log1p(deaths3),
    c_deaths_12 = log1p(deaths12),
    c_sb_12     = log1p(roll_sum(deaths_sb, 12)),
    c_ns_12     = log1p(roll_sum(deaths_ns, 12)),
    c_os_12     = log1p(roll_sum(deaths_os, 12)),
    c_events_3  = log1p(roll_sum(events, 3)),
    c_trend     = c_deaths_3 - log1p(lag(deaths3, 3)),
    c_months_since = {
      v <- numeric(n()); cnt <- 120
      for (i in seq_along(v)) { cnt <- if (!is.na(deaths3[i]) && deaths3[i] >= CFG$conflict_thr) 0 else min(cnt + 1, 120); v[i] <- cnt }
      log1p(v) },
    # ---------- Monatliche Makrodaten ----------
    m_fx_chg1    = chg(fx, 1), m_fx_chg3 = chg(fx, 3), m_fx_chg12 = chg(fx, 12),
    m_fx_vol12   = zoo::rollapplyr(m_fx_chg1, 12, sd, na.rm = TRUE, fill = NA, partial = TRUE),
    m_infl_yoy   = slog(chg(cpi, 12)),
    m_infl_chg3  = m_infl_yoy - lag(m_infl_yoy, 3),
    m_infl_mom   = slog(chg(cpi, 1)),
    m_res_chg3   = chg(reserves, 3), m_res_chg12 = chg(reserves, 12),
    m_ip_yoy     = chg(indprod, 12),
    m_stock_chg3 = chg(stocks, 3),
    m_fx_crisis12 = as.numeric(!fx_quiet),
    # ---------- Struktur (Vorjahr) ----------
    s_log_gdp_pc = log(gdp_pc), s_log_pop = log(population), s_infant_mort = infant_mortality,
    s_pop_0014 = pop_0014, s_wgi_pv = wgi_pv, s_wgi_ge = wgi_ge, s_wgi_va = wgi_va,
    # ---------- Nachrichten (Wikipedia Current Events) ----------
    n_total        = log1p(w_total),
    n_conflict     = log1p(w_conflict), n_politics = log1p(w_politics), n_crime = log1p(w_crime),
    n_econ         = log1p(w_econ), n_disaster = log1p(w_disaster), n_intl = log1p(w_intl),
    n_conflict_3   = log1p(roll_sum(w_conflict, 3)), n_total_3 = log1p(roll_sum(w_total, 3)),
    n_conflict_share = roll_sum(w_conflict, 3) / (roll_sum(w_total, 3) + 1),
    n_negativity   = roll_sum(w_neg, 3) / (roll_sum(w_neg, 3) + roll_sum(w_pos, 3) + 1),
    n_conflict_z   = rz(n_conflict), n_politics_z = rz(n_politics), n_total_z = rz(n_total),
    n_crime_z      = rz(n_crime), n_econ_z = rz(n_econ),
    n_conflict_chg3 = n_conflict_3 - log1p(lag(roll_sum(w_conflict, 3), 3)),
    n_negativity_chg = n_negativity - lag(n_negativity, 3),
    # ---------- optionale GDELT-Features ----------
    across(any_of(c("g_conflict", "g_unrest", "g_econ")), \(x) log(x + 1e-3), .names = "{sub('g_', 'gd_', .col)}_lvl"),
    across(any_of(c("g_conflict", "g_unrest", "g_econ", "g_tone")), \(x) rz(x), .names = "{sub('g_', 'gd_', .col)}_z"),
  ) |>
  # Publikationsverzug der Makrodaten: Features max. 3 Monate fortschreiben
  mutate(across(starts_with("m_"), \(x) locf_limited(x, 3))) |>
  ungroup() |>
  mutate(across(where(is.numeric), \(x) ifelse(is.finite(x), x, NA))) |>
  # Regionale und globale Gewalt (ohne eigenes Land)
  group_by(region, month) |>
  mutate(c_region_3 = log1p(pmax(sum(deaths3, na.rm = TRUE) - coalesce(deaths3, 0), 0))) |>
  group_by(month) |> mutate(c_global_3 = log1p(sum(deaths3, na.rm = TRUE))) |> ungroup()

MACRO_VARS <- grep("^m_", names(panel), value = TRUE)
panel$m_missing <- rowMeans(is.na(panel[MACRO_VARS]))

STRUCT <- c(grep("^c_", names(panel), value = TRUE), MACRO_VARS, "m_missing", grep("^s_", names(panel), value = TRUE))
NEWS   <- grep("^(n_|gd_)", names(panel), value = TRUE)
FULL   <- c(STRUCT, NEWS)

last_fx_month <- max(gem$month[gem$var == "fx"])
model_df <- panel |> filter(month >= CFG$start_month + 365)   # 12 Monate Vorlauf für Lags
saveRDS(list(panel = model_df, STRUCT = STRUCT, NEWS = NEWS, FULL = FULL,
             last_ucdp = last_ucdp, last_fx_month = last_fx_month, news_last = attr(news, "last_date")), file.path(DIR$proc, "panel.rds"))
log_msg("Panel: %d Länder-Monate; Konflikt-Basisrate %.1f %%, davon Ausbrüche %.2f %% der ruhigen Monate; Währungskrisen %.1f %%",
        nrow(model_df), 100 * mean(model_df$y_conflict, na.rm = TRUE),
        100 * mean(model_df$y_conflict[model_df$quiet], na.rm = TRUE), 100 * mean(model_df$y_fx, na.rm = TRUE))
