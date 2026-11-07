# =============================================================================
# 01_fetch_worldbank.R - Monatliche Makrodaten (Global Economic Monitor, GEM)
#                        + jährliche Strukturdaten (WDI/WGI), World Bank API
# =============================================================================
wb_json <- function(url, retries = 5) {
  for (i in seq_len(retries)) {
    res <- tryCatch(fromJSON(url), error = function(e) e)
    if (!inherits(res, "error") && length(res) >= 2) return(res)
    if (!inherits(res, "error") && !is.null(res[[1]]$message))
      stop("World-Bank-API: ", paste(unlist(res[[1]]$message), collapse = " "))
    Sys.sleep(2^i)
  }
  stop("World-Bank-API nicht erreichbar: ", url)
}
wb_series <- function(id, source, date) {
  base <- sprintf("https://api.worldbank.org/v2/country/all/indicator/%s?format=json&per_page=10000&source=%d&date=%s",
                  id, source, date)
  first <- wb_json(base); dat <- list(first[[2]])
  if (first[[1]]$pages > 1) for (p in 2:first[[1]]$pages) dat[[p]] <- wb_json(paste0(base, "&page=", p))[[2]]
  bind_rows(lapply(dat, function(d) tibble(
    iso3c = ifelse(nchar(d$countryiso3code) == 3, d$countryiso3code, d$country$id),
    date = d$date, value = as.numeric(d$value)))) |>
    filter(!is.na(value), nchar(iso3c) == 3)
}

GEM <- tribble(            # Monatsdaten, Quelle 15 (Global Economic Monitor)
  ~var,       ~id,
  "fx",       "DPANUSSPB",   # Wechselkurs Landeswährung je USD
  "cpi",      "CPTOTNSXN",   # Konsumentenpreisindex
  "reserves", "TOTRESV",     # Währungsreserven
  "indprod",  "IPTOTSAKD",   # Industrieproduktion
  "stocks",   "DSTKMKTXD"    # Aktienindex (USD)
)
ANNUAL <- tribble(
  ~var,               ~id,                 ~source,
  "population",       "SP.POP.TOTL",       2,
  "gdp_pc",           "NY.GDP.PCAP.KD",    2,
  "infant_mortality", "SP.DYN.IMRT.IN",    2,
  "pop_0014",         "SP.POP.0014.TO.ZS", 2,
  "wgi_pv",           "GOV_WGI_PV.EST",    3,
  "wgi_ge",           "GOV_WGI_GE.EST",    3,
  "wgi_va",           "GOV_WGI_VA.EST",    3
)

f_gem <- file.path(DIR$raw, "gem_monthly.rds"); f_ann <- file.path(DIR$raw, "wb_annual.rds")
f_ctry <- file.path(DIR$raw, "countries.rds")

if (!file.exists(f_gem) || CFG$refresh) {
  rng <- sprintf("%sM01:%sM12", format(CFG$start_month, "%Y") , format(Sys.Date(), "%Y"))
  gem <- map_dfr(seq_len(nrow(GEM)), function(i) {
    d <- wb_series(GEM$id[i], 15, rng)
    log_msg("  GEM %-9s %6d Werte, bis %s", GEM$var[i], nrow(d), max(d$date))
    mutate(d, var = GEM$var[i], month = as.Date(paste0(sub("M", "-", date), "-01")))
  })
  saveRDS(select(gem, iso3c, month, var, value), f_gem)

  ann <- map_dfr(seq_len(nrow(ANNUAL)), function(i) {
    d <- wb_series(ANNUAL$id[i], ANNUAL$source[i], sprintf("2005:%s", format(Sys.Date(), "%Y")))
    mutate(d, var = ANNUAL$var[i], year = as.integer(date))
  })
  saveRDS(select(ann, iso3c, year, var, value), f_ann)

  meta <- wb_json("https://api.worldbank.org/v2/country?format=json&per_page=500")[[2]]
  ctry <- tibble(iso3c = meta$id, country = meta$name, region = meta$region$value) |>
    filter(region != "Aggregates")
  pop <- ann |> filter(var == "population") |> group_by(iso3c) |> slice_max(year, n = 1) |>
    select(iso3c, pop = value)
  ctry <- ctry |> left_join(pop, by = "iso3c") |>
    mutate(gwn = suppressWarnings(countrycode(iso3c, "iso3c", "gwn",
                                              custom_match = c(SRB = 340, XKX = 347, SSD = 626)))) |>
    filter(pop >= CFG$min_pop, !is.na(gwn))
  saveRDS(ctry, f_ctry)
  log_msg("World Bank: %d Länder (>= %s Einwohner, staatlich)", nrow(ctry), format(CFG$min_pop, big.mark = "'"))
} else log_msg("World-Bank-Daten aus Cache")
