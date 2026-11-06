# =============================================================================
# 02_fetch_ungdc.R - Textdaten: UN General Debate Corpus (UNGDC, 1946-2025)
# Baturo, Dasandi & Mikhaylov (2017), Harvard Dataverse doi:10.7910/DVN/0TJX8Y
# Jede Rede eines Staates vor der UN-Generalversammlung = ein Dokument (Land, Jahr).
# =============================================================================

f_speeches <- file.path(DIR$proc, "speeches.rds")

UNGDC_MIRROR <- list(url = "https://github.com/jradius/un-general-debates",
                     commit = "d1f2d6f54e0e5b61a2b1639b6a664a4b07ca4382",   # fixiert -> reproduzierbar
                     path = "data/UNGDC_1946-2022/TXT")

# Quelle 1 (bevorzugt): offizielles Dataverse-Archiv (1946-2025), falls vorhanden bzw. per Guestbook ladbar
get_ungdc_dataverse <- function() {
  meta  <- fromJSON(sprintf(
    "https://dataverse.harvard.edu/api/datasets/:persistentId/?persistentId=%s", CFG$ungdc_doi))
  files <- meta$data$latestVersion$files$dataFile
  sel   <- grepl("^UNGDC.*\\.tar\\.gz$", files$filename)
  tar_path <- file.path(DIR$raw, files$filename[sel][1])
  if (!file.exists(tar_path)) {
    # Dataverse verlangt einen Guestbook-Eintrag (Name, E-Mail, Institution, Position).
    gb <- Sys.getenv(c("UNGDC_NAME", "UNGDC_EMAIL", "UNGDC_INSTITUTION", "UNGDC_POSITION"))
    if (any(gb == "")) return(NULL)
    log_msg("Lade %s von Harvard Dataverse ...", basename(tar_path))
    body <- toJSON(list(guestbookResponse = list(name = gb[[1]], email = gb[[2]],
                   institution = gb[[3]], position = gb[[4]], answers = list())), auto_unbox = TRUE)
    r <- httr::POST(sprintf("https://dataverse.harvard.edu/api/access/datafile/%s?signed=true", files$id[sel][1]),
                    body = body, httr::content_type_json())
    httr::stop_for_status(r)
    download.file(httr::content(r, as = "parsed")$data$signedUrl, tar_path, mode = "wb", quiet = TRUE)
  }
  exdir <- file.path(DIR$raw, "ungdc_dataverse")
  if (!dir.exists(exdir)) untar(tar_path, exdir = exdir)
  exdir
}

# Quelle 2 (Fallback): öffentliche CC0-Kopie auf GitHub (Reden 1946-2022), per git sparse checkout
get_ungdc_github <- function() {
  exdir <- file.path(DIR$raw, "ungdc_github")
  if (!dir.exists(file.path(exdir, UNGDC_MIRROR$path))) {
    log_msg("Lade UNGDC-Kopie von GitHub (%s @ %s) ...", UNGDC_MIRROR$url, substr(UNGDC_MIRROR$commit, 1, 7))
    unlink(exdir, recursive = TRUE)
    git <- function(...) {
      st <- system2("git", c("-c", "gc.auto=0", ...), stdout = FALSE, stderr = FALSE)
      if (st != 0) stop("git-Befehl fehlgeschlagen: git ", paste(c(...), collapse = " "))
    }
    git("clone", "--quiet", "--filter=blob:none", "--no-checkout", "--sparse", UNGDC_MIRROR$url, shQuote(exdir))
    git("-C", shQuote(exdir), "sparse-checkout", "set", "--no-cone", shQuote(paste0("/", UNGDC_MIRROR$path, "/")))
    git("-C", shQuote(exdir), "checkout", "--quiet", UNGDC_MIRROR$commit)
  }
  file.path(exdir, UNGDC_MIRROR$path)
}

if (!file.exists(f_speeches) || CFG$refresh) {
  exdir <- tryCatch(get_ungdc_dataverse(), error = function(e) {
    log_msg("Dataverse nicht verfügbar (%s)", conditionMessage(e)); NULL })
  if (is.null(exdir)) {
    log_msg("Kein Dataverse-Archiv/Guestbook -> verwende GitHub-Kopie")
    exdir <- get_ungdc_github()
  }

  txt  <- list.files(exdir, pattern = "\\.txt$", recursive = TRUE, full.names = TRUE)
  m    <- str_match(basename(txt), "^([A-Z]{2,4})_(\\d+)_(\\d{4})\\.txt$")
  keep <- !is.na(m[, 1]) & as.integer(m[, 4]) >= min(CFG$years) - 1
  log_msg("UNGDC: %d Reden gefunden, %d ab %d", sum(!is.na(m[, 1])), sum(keep), min(CFG$years) - 1)

  read_one <- function(p) {
    x <- readLines(p, warn = FALSE, encoding = "UTF-8")
    x <- iconv(paste(x, collapse = " "), "UTF-8", "UTF-8", sub = " ")
    str_squish(x)
  }
  speeches <- tibble(iso3c = m[keep, 2], year = as.integer(m[keep, 4]),
                     text = vapply(txt[keep], read_one, character(1), USE.NAMES = FALSE)) |>
    group_by(iso3c, year) |> summarise(text = paste(text, collapse = " "), .groups = "drop")
  saveRDS(speeches, f_speeches)
} else {
  log_msg("UNGDC-Reden aus Cache (%s)", f_speeches)
}
