# =============================================================================
# 03_fetch_news.R - Schnelle Textdaten: Wikipedia "Portal:Current events"
#
# Täglich von Freiwilligen gepflegter Nachrichtenticker mit Quellen (Reuters, BBC, AP, ...),
# gegliedert in Rubriken wie "Armed conflicts and attacks", "Politics and elections",
# "Business and economy". Die Meldungen erscheinen am selben Tag.
#
# Text Mining pro Meldung:
#   * Rubrik (Konflikt, Politik, Kriminalität, Wirtschaft, Katastrophen, Diplomatie, ...)
#   * Erwähnte Länder (Wörterbuch aus Ländernamen und Adjektiven, inkl. übergeordneter Themenzeilen)
#   * Tonalität (Bing-Lexikon: Anteil negativer Wörter)
# -> Länder-Monats-Zeitreihen ab 2017; pro Monat genügt EINE API-Anfrage (bis 31 Tagesseiten).
# =============================================================================

NEWS_CATEGORIES <- c(
  "armed conflicts and attacks" = "conflict", "attacks and armed conflicts" = "conflict",
  "disasters and accidents" = "disaster", "politics and elections" = "politics",
  "law and crime" = "crime", "business and economy" = "econ", "business and economics" = "econ",
  "international relations" = "intl", "health and environment" = "health", "health" = "health",
  "health and medicine" = "health", "environment" = "health")

# Ländererkennung: Namen, Varianten, Adjektive (ICU-Regex, Gross-/Kleinschreibung egal)
COUNTRY_PATTERNS <- c(
  AFG = "afghanistan|afghan", ALB = "albania", DZA = "algeria", AGO = "angola", ARG = "argentin",
  ARM = "armenia", AUS = "australia", AUT = "austria", AZE = "azerbaijan", BGD = "bangladesh",
  BLR = "belarus", BEL = "belgi", BEN = "benin", BOL = "bolivia", BIH = "bosnia|herzegovina",
  BWA = "botswana", BRA = "brazil", BGR = "bulgaria", BFA = "burkina faso|burkinab", BDI = "burundi",
  KHM = "cambodia", CMR = "cameroon", CAN = "canada|canadian", CAF = "central african republic",
  TCD = "chad(ian)?\\b", CHL = "chile", CHN = "china|chinese|beijing", COL = "colombia",
  COD = "democratic republic of (the )?congo|dr congo|\\bdrc\\b|kinshasa|congolese",
  COG = "(?<!democratic )republic of (the )?congo|congo-brazzaville|brazzaville",
  CRI = "costa rica", CIV = "ivory coast|ivorian|c[oô]te d.ivoire", HRV = "croatia", CUB = "cuba",
  CZE = "czech", DNK = "denmark|danish", DOM = "dominican republic", DJI = "djibouti", GNQ = "equatorial guinea", ECU = "ecuador", EGY = "egypt",
  SLV = "el salvador|salvadoran", ERI = "eritrea", EST = "estonia", SWZ = "eswatini|swaziland",
  ETH = "ethiopia", FIN = "finland|finnish", FRA = "france|french", GAB = "gabon", GMB = "gambia",
  GEO = "tbilisi|georgian government|georgia \\(country\\)", DEU = "germany|german", GHA = "ghana",
  GRC = "greece|greek", GTM = "guatemala", GIN = "(?<!new |equatorial |papua new )guinea(?!-bissau| ?bissau)|guinean",
  GNB = "guinea-bissau", HTI = "haiti", HND = "hondura", HUN = "hungar", IND = "india(?!n ocean|na)",
  IDN = "indonesia", IRN = "iran", IRQ = "iraq", IRL = "republic of ireland|(?<!northern )ireland|irish",
  ISR = "israel", ITA = "italy|italian", JAM = "jamaica", JPN = "japan", JOR = "jordan",
  KAZ = "kazakh", KEN = "kenya", PRK = "north korea", KOR = "south korea", KWT = "kuwait",
  KGZ = "kyrgyz", LAO = "\\blaos\\b|\\blao\\b", LVA = "latvia", LBN = "leban", LSO = "lesotho",
  LBR = "liberia", LBY = "libya", LTU = "lithuania", MDG = "madagascar|malagasy", MWI = "malawi",
  MYS = "malaysia", MLI = "\\bmali(an)?\\b", MRT = "mauritania", MUS = "mauritius", MEX = "mexic",
  MDA = "moldova", MNG = "mongolia", MAR = "morocc", MOZ = "mozambi", MMR = "myanmar|burm",
  NAM = "namibia", NPL = "nepal", NLD = "netherlands|dutch", NZL = "new zealand", NIC = "nicaragua",
  NER = "\\bniger\\b|nigerien", NGA = "nigeria", MKD = "north macedonia|macedonia", NOR = "norw",
  OMN = "\\boman", PAK = "pakistan", PAN = "panama", PNG = "papua new guinea", PRY = "paraguay",
  PER = "\\bperu", PHL = "philippine|filipino", POL = "poland|polish", PRT = "portug", QAT = "qatar",
  ROU = "romania", RUS = "russia|kremlin|moscow", RWA = "rwanda", SAU = "saudi", SEN = "senegal",
  SRB = "serbia", SLE = "sierra leone", SGP = "singapore", SVK = "slovakia", SVN = "slovenia",
  SOM = "somali", ZAF = "south africa", SSD = "south sudan", ESP = "spain|spanish", LKA = "sri lanka",
  SDN = "(?<!south )sudan", SWE = "sweden|swedish", CHE = "switzerland|swiss", SYR = "syria",
  TJK = "tajik", TZA = "tanzania", THA = "thailand|\\bthai\\b", TLS = "timor", TGO = "\\btogo",
  TTO = "trinidad", TUN = "tunisia", TUR = "turkey|turkish|t[uü]rkiye", TKM = "turkmen",
  UGA = "uganda", UKR = "ukrain|kyiv", ARE = "united arab emirates|emirati|\\buae\\b",
  GBR = "united kingdom|\\bbritish|\\bbritain|\\buk\\b|england|scotland|wales",
  USA = "united states|\\bu\\.s\\.|(?<!latin |south |central |north )american(?! samoa)|washington, d", URY = "uruguay", UZB = "uzbek",
  VEN = "venezuela", VNM = "vietnam|viet nam", YEM = "yemen", ZMB = "zambia", ZWE = "zimbabwe",
  XKX = "kosovo", PSE = "palestin|gaza|west bank", BHR = "bahrain", CYP = "cyprus|cypriot")
COUNTRY_PATTERNS <- setNames(paste0("\\b(?:", COUNTRY_PATTERNS, ")"), names(COUNTRY_PATTERNS))

clean_wikitext <- function(x) {
  x |>
    str_replace_all("\\[https?://[^ \\]]+ ?([^\\]]*)\\]", " ") |>          # Quellenlinks
    str_replace_all("\\[\\[(?:[^\\]|]*\\|)?([^\\]]*)\\]\\]", "\\1") |>     # [[Ziel|Text]] -> Text
    str_replace_all("\\{\\{[^}]*\\}\\}", " ") |> str_replace_all("<[^>]+>", " ") |>
    str_replace_all("'{2,}", "") |> str_squish()
}
# Ziele von Wiki-Links zusätzlich behalten (z. B. "[[Sudanese civil war|Fighting]]")
link_targets <- function(x) paste(str_match_all(x, "\\[\\[([^\\]|]*)")[[1]][, 2], collapse = " ")

parse_day <- function(wikitext, date) {
  lines <- strsplit(wikitext, "\n", fixed = TRUE)[[1]]
  cat <- "other"; stack <- character(0); items <- list()
  for (ln in lines) {
    h <- tolower(str_squish(str_replace_all(ln, "^;|'''|:$", "")))
    if (!startsWith(ln, "*") && h %in% names(NEWS_CATEGORIES)) { cat <- NEWS_CATEGORIES[[h]]; stack <- character(0); next }
    if (!startsWith(ln, "*")) next
    depth <- nchar(str_extract(ln, "^\\*+")); body <- sub("^\\*+", "", ln)
    txt <- paste(clean_wikitext(body), link_targets(body))
    stack <- c(stack[seq_len(min(length(stack), depth - 1))], txt)
    if (grepl("\\[https?://", body)) {                                     # echte Meldung (mit Quelle)
      items[[length(items) + 1]] <- tibble(date = date, category = cat,
                                           text = clean_wikitext(body), context = paste(stack, collapse = " | "))
    }
  }
  bind_rows(items)
}

wiki_month <- function(m) {
  days  <- seq(m, add_months(m, 1) - 1, by = "day")
  days  <- days[days <= Sys.Date()]
  if (!length(days)) return(NULL)
  titles <- sprintf("Portal:Current events/%s %s %d", format(days, "%Y"), month.name[as.integer(format(days, "%m"))],
                    as.integer(format(days, "%d")))
  url <- paste0("https://en.wikipedia.org/w/api.php?action=query&prop=revisions&rvprop=content&rvslots=main",
                "&format=json&formatversion=2&titles=", URLencode(paste(titles, collapse = "|"), reserved = TRUE))
  for (i in 1:5) {
    js <- tryCatch(fromJSON(paste(readLines(url(url, headers = c(`User-Agent` = "global-risk-early-warning/1.0 (research; R)")),
                                            warn = FALSE), collapse = "\n"), simplifyVector = FALSE),
                   error = function(e) NULL)
    if (!is.null(js)) break
    Sys.sleep(2^i)
  }
  if (is.null(js)) stop("Wikipedia-API nicht erreichbar für ", format(m, "%Y-%m"))
  map_dfr(js$query$pages, function(pg) {
    if (isTRUE(pg$missing) || is.null(pg$revisions)) return(NULL)
    # Datum sprachunabhängig parsen (kein %B: unter z. B. französischem Locale hiesse "April" "avril")
    parts <- strsplit(sub("^Portal:Current events/", "", pg$title), " ", fixed = TRUE)[[1]]
    d <- as.Date(sprintf("%s-%02d-%02d", parts[1], match(parts[2], month.name), as.integer(parts[3])))
    parse_day(pg$revisions[[1]]$slots$main$content, d)
  })
}

f_news_items <- file.path(DIR$proc, "news_items.rds")
f_news <- file.path(DIR$proc, "news_monthly.rds")
cache_dir <- file.path(DIR$raw, "wikinews_v2"); dir.create(cache_dir, showWarnings = FALSE)   # v2: sprachunabhängige Datumswerte
news_months <- seq(CFG$gdelt_start, month_floor(Sys.Date()), by = "month")
log_msg("Wikipedia Current Events: %d Monate", length(news_months))
items <- map_dfr(news_months, function(m) {
  f <- file.path(cache_dir, paste0(format(m, "%Y-%m"), ".rds"))
  recent <- m >= add_months(month_floor(Sys.Date()), -2)    # nur die letzten 3 Monate neu laden (Archiv ist stabil)
  if (file.exists(f) && !recent) return(readRDS(f))
  d <- wiki_month(m); Sys.sleep(1)
  if (!is.null(d)) saveRDS(d, f)
  d
})
if (!nrow(items) || mean(is.na(items$date)) > 0.01)
  stop("Wikipedia-Meldungen ohne gültiges Datum (", sum(is.na(items$date)), " von ", nrow(items),
       "). Bitte den Ordner ", cache_dir, " löschen und neu starten.")
log_msg("  %d Meldungen geparst (%s bis %s)", nrow(items), min(items$date), max(items$date))

# Ländererkennung und Tonalität pro Meldung
ctry <- readRDS(f_ctry)
pats <- COUNTRY_PATTERNS[names(COUNTRY_PATTERNS) %in% ctry$iso3c]
txt_all <- tolower(paste(items$text, items$context))
hits <- map_dfr(names(pats), function(iso) {
  w <- which(str_detect(txt_all, regex(pats[[iso]], ignore_case = TRUE)))
  if (length(w)) tibble(item = w, iso3c = iso) else NULL
})
bing <- tidytext::get_sentiments("bing")
toks <- str_extract_all(tolower(items$text), "[a-z']+")
items$neg <- vapply(toks, \(w) sum(w %in% bing$word[bing$sentiment == "negative"]), 0)
items$pos <- vapply(toks, \(w) sum(w %in% bing$word[bing$sentiment == "positive"]), 0)
saveRDS(items, f_news_items)

news_monthly <- hits |>
  left_join(mutate(items, item = row_number(), month = month_floor(date)) |> select(item, month, category, neg, pos),
            by = "item") |>
  group_by(iso3c, month) |>
  summarise(total = n(), conflict = sum(category == "conflict"), politics = sum(category == "politics"),
            crime = sum(category == "crime"), econ = sum(category == "econ"), disaster = sum(category == "disaster"),
            intl = sum(category == "intl"), neg = sum(neg), pos = sum(pos), .groups = "drop")
attr(news_monthly, "last_date") <- max(items$date)
saveRDS(news_monthly, f_news)
log_msg("News: %d Länder-Monate mit Meldungen, %d Länder, letzte Meldung %s",
        nrow(news_monthly), n_distinct(news_monthly$iso3c), max(items$date))
