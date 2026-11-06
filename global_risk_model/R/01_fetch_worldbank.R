# =============================================================================
# 01_fetch_worldbank.R - Strukturierte Daten: World Bank WDI + WGI (öffentliche API)
# =============================================================================

INDICATORS <- tribble(
  ~var,              ~id,                    ~source, ~dimension,
  # Ereignisse / Hazard
  "gdp_growth",      "NY.GDP.MKTP.KD.ZG",    2, "Makro",
  "inflation",       "FP.CPI.TOTL.ZG",       2, "Makro",
  "battle_deaths",   "VC.BTL.DETH",          2, "Konflikt",
  "fx_rate",         "PA.NUS.FCRF",          2, "Makro",
  "homicide",        "VC.IHR.PSRC.P5",       2, "Konflikt",
  "military_gdp",    "MS.MIL.XPND.GD.ZS",    2, "Konflikt",
  # Makro-Verwundbarkeit
  "gdp_pc",          "NY.GDP.PCAP.KD",       2, "Makro",
  "unemployment",    "SL.UEM.TOTL.ZS",       2, "Sozial",
  "current_account", "BN.CAB.XOKA.GD.ZS",    2, "Makro",
  "reserves_months", "FI.RES.TOTL.MO",       2, "Makro",
  "ext_debt_gni",    "DT.DOD.DECT.GN.ZS",    2, "Makro",
  "trade_gdp",       "NE.TRD.GNFS.ZS",       2, "Makro",
  "resource_rents",  "NY.GDP.TOTL.RT.ZS",    2, "Makro",
  "oda_gni",         "DT.ODA.ODAT.GN.ZS",    2, "Sozial",
  # Demografie / Soziales
  "population",      "SP.POP.TOTL",          2, "Sozial",
  "pop_growth",      "SP.POP.GROW",          2, "Sozial",
  "pop_0014",        "SP.POP.0014.TO.ZS",    2, "Sozial",
  "urban_growth",    "SP.URB.GROW",          2, "Sozial",
  "infant_mortality","SP.DYN.IMRT.IN",       2, "Sozial",
  # Governance (Worldwide Governance Indicators)
  "wgi_pv",          "GOV_WGI_PV.EST",       3, "Governance",
  "wgi_ge",          "GOV_WGI_GE.EST",       3, "Governance",
  "wgi_rl",          "GOV_WGI_RL.EST",       3, "Governance",
  "wgi_cc",          "GOV_WGI_CC.EST",       3, "Governance",
  "wgi_va",          "GOV_WGI_VA.EST",       3, "Governance",
  "wgi_rq",          "GOV_WGI_RQ.EST",       3, "Governance"
)

wb_json <- function(url, retries = 5) {
  for (i in seq_len(retries)) {
    res <- tryCatch(fromJSON(url), error = function(e) e)
    if (!inherits(res, "error") && length(res) >= 2) return(res)
    if (!inherits(res, "error") && !is.null(res[[1]]$message))      # API-Fehlermeldung: kein Retry
      stop("World-Bank-API: ", paste(unlist(res[[1]]$message), collapse = " "), " (", url, ")")
    Sys.sleep(2^i)
  }
  stop("World-Bank-API nicht erreichbar: ", url,
       if (inherits(res, "error")) paste0(" (", conditionMessage(res), ")") else "")
}

wb_indicator <- function(id, source = 2, years = CFG$years) {
  base <- sprintf(
    "https://api.worldbank.org/v2/country/all/indicator/%s?format=json&per_page=20000&date=%d:%d&source=%d",
    id, min(years), max(years), source)
  first <- wb_json(base)
  pages <- as.integer(first[[1]]$pages)
  dat   <- list(first[[2]])
  if (pages > 1) for (pg in 2:pages) dat[[pg]] <- wb_json(paste0(base, "&page=", pg))[[2]]
  bind_rows(lapply(dat, function(d)
    tibble(iso3c = d$countryiso3code, year = as.integer(d$date), value = as.numeric(d$value)))) |>
    filter(!is.na(value), nchar(iso3c) == 3)
}

wb_countries <- function() {
  x <- wb_json("https://api.worldbank.org/v2/country?format=json&per_page=500")[[2]]
  tibble(iso3c = x$id, country = x$name, region = x$region$value, income = x$incomeLevel$value) |>
    filter(region != "Aggregates")
}

f_wb   <- file.path(DIR$raw, "worldbank_long.rds")
f_ctry <- file.path(DIR$raw, "worldbank_countries.rds")

if (!file.exists(f_wb) || CFG$refresh) {
  log_msg("Lade %d World-Bank-Indikatoren ...", nrow(INDICATORS))
  wb_long <- pmap_dfr(INDICATORS, function(var, id, source, dimension) {
    d <- tryCatch(wb_indicator(id, source), error = function(e) {
      warning("Indikator ", id, " übersprungen: ", conditionMessage(e)); NULL })
    if (is.null(d)) return(NULL)
    log_msg("  %-17s %-20s %6d Werte, %d-%d", var, id, nrow(d), min(d$year), max(d$year))
    mutate(d, var = var)
  })
  saveRDS(wb_long, f_wb)
  saveRDS(wb_countries(), f_ctry)
} else {
  log_msg("World-Bank-Daten aus Cache (%s)", f_wb)
}
