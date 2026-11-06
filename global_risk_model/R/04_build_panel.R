# =============================================================================
# 04_build_panel.R - Länder-Jahr-Panel, Zielvariable, Feature Engineering
#
# Zielvariable  y(t) = 1, wenn im Folgejahr t+1 mindestens eines eintritt:
#   * Gewaltsamer Konflikt:   >= 25 kampfbezogene Todesopfer (UCDP via WDI)
#   * Wirtschaftlicher Einbruch: reales BIP-Wachstum < -3 %
#   * Inflationskrise:        Inflation > 30 %
# Features stammen ausschliesslich aus Jahr t (oder früher).
# =============================================================================

wb_long   <- readRDS(f_wb)
countries <- readRDS(f_ctry)
text_feat <- readRDS(f_text)

last_conflict_year <- max(wb_long$year[wb_long$var == "battle_deaths"])
last_feature_year  <- max(wb_long$year[wb_long$var == "gdp_growth"])
log_msg("Konfliktdaten bis %d, Makrodaten bis %d", last_conflict_year, last_feature_year)

locf_limited <- function(x, max_gap = CFG$locf_max) {
  last <- NA_real_; gap <- Inf
  for (i in seq_along(x)) {
    if (!is.na(x[i])) { last <- x[i]; gap <- 0 }
    else { gap <- gap + 1; if (gap <= max_gap) x[i] <- last }
  }
  x
}
slog  <- function(x) sign(x) * log1p(abs(x))
clamp <- function(x, lo, hi) pmin(pmax(x, lo), hi)

panel <- wb_long |>
  filter(iso3c %in% countries$iso3c) |>
  pivot_wider(names_from = var, values_from = value) |>
  (\(d) { for (v in setdiff(INDICATORS$var, names(d))) d[[v]] <- NA_real_; d })() |>
  right_join(expand_grid(iso3c = countries$iso3c, year = CFG$years), by = c("iso3c", "year")) |>
  left_join(countries, by = "iso3c") |>
  arrange(iso3c, year) |>
  group_by(iso3c) |>
  mutate(
    # --- Ereignis-Komponenten im Jahr t (aus Rohdaten, vor jeder Imputation) ---
    battle_deaths = case_when(!is.na(battle_deaths) ~ battle_deaths,
                              year <= last_conflict_year ~ 0,
                              TRUE ~ NA_real_),
    conflict_t = battle_deaths >= 25,
    macro_t    = case_when(gdp_growth < -3 | inflation > 30 ~ TRUE,
                           !is.na(gdp_growth) ~ FALSE, TRUE ~ NA),
    crisis_t   = case_when(conflict_t | macro_t ~ 1, !is.na(conflict_t) & !is.na(macro_t) ~ 0,
                           TRUE ~ NA_real_),
    # --- Zielvariable: Krise im Folgejahr ---
    y          = lead(crisis_t),
    y_conflict = as.numeric(lead(conflict_t)),
    y_macro    = as.numeric(lead(macro_t)),
    # Für das Prognosejahr (t > letzte Konfliktdaten): Konfliktstatus fortschreiben
    battle_deaths_f = locf_limited(battle_deaths, 2),
    conflict_now = as.numeric(coalesce(battle_deaths_f >= 25, FALSE)),
    macro_now    = as.numeric(coalesce(macro_t, FALSE)),
    crisis_now   = pmax(conflict_now, macro_now),
    # --- Krisenhistorie ---
    crisis_count_5y = zoo::rollapplyr(crisis_now, 5, sum, partial = TRUE),
    years_since_crisis = {
      v <- numeric(n()); cnt <- 10
      for (i in seq_along(v)) { cnt <- if (crisis_now[i] == 1) 0 else min(cnt + 1, 25); v[i] <- cnt }
      v },
    # --- Transformationen ---
    deaths_log      = log1p(battle_deaths_f),
    fx_change       = slog(100 * (fx_rate / lag(fx_rate) - 1)),
    log_gdp_pc      = log(gdp_pc),
    log_pop         = log(population),
    inflation_slog  = slog(inflation),
    gdp_growth      = clamp(gdp_growth, -30, 30),
    gdp_growth_3y   = zoo::rollapplyr(gdp_growth, 3, mean, na.rm = TRUE, partial = TRUE),
    d_inflation     = inflation_slog - lag(inflation_slog),
    d_wgi_pv        = wgi_pv - lag(wgi_pv, 2),
    homicide_log    = log1p(homicide)
  ) |>
  ungroup()

STRUCT <- c("crisis_now", "conflict_now", "macro_now", "crisis_count_5y", "years_since_crisis",
            "deaths_log", "military_gdp", "homicide_log",
            "gdp_growth", "gdp_growth_3y", "inflation_slog", "d_inflation", "fx_change",
            "log_gdp_pc", "unemployment", "current_account", "reserves_months", "ext_debt_gni",
            "trade_gdp", "resource_rents", "oda_gni",
            "log_pop", "pop_growth", "pop_0014", "urban_growth", "infant_mortality",
            "wgi_pv", "wgi_ge", "wgi_rl", "wgi_cc", "wgi_va", "wgi_rq", "d_wgi_pv",
            "regional_crisis_share", "global_crisis_share", "struct_missing_share")

locf_vars <- setdiff(STRUCT, c("crisis_now", "conflict_now", "macro_now", "crisis_count_5y",
                               "years_since_crisis", "deaths_log", "regional_crisis_share",
                               "global_crisis_share", "struct_missing_share"))

panel <- panel |>
  mutate(struct_missing_share = rowMeans(is.na(across(all_of(locf_vars))))) |>
  group_by(iso3c) |> mutate(across(all_of(locf_vars), locf_limited)) |> ungroup() |>
  # Ansteckung / globale Lage (ohne eigenes Land)
  group_by(region, year) |>
  mutate(regional_crisis_share = (sum(crisis_now) - crisis_now) / pmax(n() - 1, 1)) |>
  group_by(year) |> mutate(global_crisis_share = mean(crisis_now)) |> ungroup()

# --- Textfeatures anhängen (Rede im Jahr t, Lücken max. 2 Jahre fortgeschrieben) ---
TEXT <- setdiff(names(text_feat), c("iso3c", "year"))
panel <- panel |>
  left_join(text_feat, by = c("iso3c", "year")) |>
  group_by(iso3c) |>
  mutate(txt_has_speech = as.numeric(!is.na(txt_sentiment)),
         across(all_of(TEXT), \(x) locf_limited(x, 2)),
         txt_d_sentiment = txt_sentiment - lag(txt_sentiment),
         txt_d_conflict  = txt_lex_conflict - lag(txt_lex_conflict)) |>
  ungroup()
TEXT <- c(TEXT, "txt_has_speech", "txt_d_sentiment", "txt_d_conflict")
FULL <- c(STRUCT, TEXT)

matched <- mean(unique(text_feat$iso3c) %in% countries$iso3c)
log_msg("Text-Länder-Match mit World Bank: %.0f %%", 100 * matched)

model_df <- panel |>
  filter(year >= 1991, year <= last_conflict_year - 1, !is.na(y),
         struct_missing_share < 0.6) |>
  select(iso3c, country, region, income, year, y, y_conflict, y_macro, all_of(FULL))

forecast_df <- panel |>
  filter(year == last_feature_year, struct_missing_share < 0.6) |>
  select(iso3c, country, region, income, year, all_of(FULL))

saveRDS(list(panel = panel, model_df = model_df, forecast_df = forecast_df,
             STRUCT = STRUCT, TEXT = TEXT, FULL = FULL,
             last_conflict_year = last_conflict_year, last_feature_year = last_feature_year),
        file.path(DIR$proc, "panel.rds"))
log_msg("Modell-Datensatz: %d Länder-Jahre, %d Länder, Krisenrate %.1f %%",
        nrow(model_df), n_distinct(model_df$iso3c), 100 * mean(model_df$y))
