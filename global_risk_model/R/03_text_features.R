# =============================================================================
# 03_text_features.R - Text Mining der UN-Reden
#   (a) Lexikon-Sentiment (Bing Liu Lexikon, tidytext)
#   (b) Risiko-Wörterbücher (Konflikt, Wirtschaftsstress, Humanitär, ...)
#   (c) Latent Semantic Analysis (TF-IDF + truncated SVD), nur auf Trainingsjahren gefittet
# =============================================================================

f_text <- file.path(DIR$proc, "text_features.rds")
f_lsa  <- file.path(DIR$proc, "lsa_terms.rds")

RISK_LEXICON <- list(
  conflict    = "^(war|wars|warfare|conflict|armed|militar|violen|attack|fighting|hostilit|aggress|invasion|invad|occupation|insurgen|rebel|militia|weapon|bomb|killing|killed|massacre|genocide|ceasefire|troops|shelling)",
  terrorism   = "^(terror|extremis|jihad|radicali)",
  econ_stress = "^(debt|deficit|recession|inflation|unemploy|poverty|austerity|default|devaluat|downturn|stagnat|bankrupt|insolven|indebted)",
  humanitarian= "^(refugee|displace|famine|hunger|starv|humanitarian|migrant|asylum|malnutrition)",
  disaster    = "^(drought|flood|earthquake|hurricane|cyclone|tsunami|disaster|climate|warming|desertif|typhoon)",
  health      = "^(pandemic|epidemic|covid|ebola|hiv|aids|malaria|cholera|virus)",
  instability = "^(coup|unconstitutional|corrupt|instabil|crisis|crises|unrest|turmoil|sanction|threat)",
  cooperation = "^(cooperat|partnership|dialogue|peaceful|prosper|solidarity|multilateral)"
)

if (!file.exists(f_text) || CFG$refresh) {
  sp <- readRDS(f_speeches)
  log_msg("Tokenisiere %d Reden ...", nrow(sp))
  stop_w <- unique(tidytext::stop_words$word)
  toks <- tokenize_words(sp$text, lowercase = TRUE, strip_punct = TRUE, strip_numeric = TRUE)
  n_raw <- lengths(toks)
  toks <- lapply(toks, function(w) w[nchar(w) > 2 & !(w %in% stop_w)])

  # Dokument-Term-Matrix (sparse)
  all_w <- unlist(toks, use.names = FALSE)
  vocab <- unique(all_w)
  dtm <- sparseMatrix(i = rep(seq_along(toks), lengths(toks)), j = match(all_w, vocab), x = 1,
                      dims = c(length(toks), length(vocab)), dimnames = list(NULL, vocab))
  rm(all_w, toks); invisible(gc())
  n_tok <- pmax(rowSums(dtm), 1)
  log_msg("DTM: %d Dokumente x %d Terme", nrow(dtm), ncol(dtm))

  # (a) Sentiment
  bing <- tidytext::get_sentiments("bing")
  cnt <- function(words) { w <- intersect(words, vocab); if (!length(w)) 0 else rowSums(dtm[, w, drop = FALSE]) }
  pos <- cnt(bing$word[bing$sentiment == "positive"])
  neg <- cnt(bing$word[bing$sentiment == "negative"])

  feats <- tibble(iso3c = sp$iso3c, year = sp$year,
                  txt_log_length = log(n_raw + 1),
                  txt_sentiment  = (pos - neg) / (pos + neg + 1),
                  txt_negativity = 1000 * neg / n_tok)

  # (b) Risiko-Wörterbücher (Treffer pro 1000 Tokens)
  for (nm in names(RISK_LEXICON)) {
    feats[[paste0("txt_lex_", nm)]] <- 1000 * cnt(vocab[grepl(RISK_LEXICON[[nm]], vocab)]) / n_tok
  }
  feats$txt_risk_minus_coop <- with(feats, txt_lex_conflict + txt_lex_terrorism + txt_lex_econ_stress +
                                      txt_lex_humanitarian + txt_lex_instability - txt_lex_cooperation)

  # (c) LSA: Vokabular, IDF und SVD nur aus Reden <= lsa_fit_until (keine Zukunftsinformation)
  fit_rows <- which(sp$year <= CFG$lsa_fit_until)
  df_fit   <- colSums(dtm[fit_rows, ] > 0)
  keep     <- which(df_fit >= 0.01 * length(fit_rows) & df_fit <= 0.6 * length(fit_rows))
  X <- dtm[, keep]
  X@x <- log1p(X@x)                                    # sublineares TF
  idf <- log(length(fit_rows) / df_fit[keep])
  X <- X %*% Diagonal(x = idf)
  X <- Diagonal(x = 1 / pmax(sqrt(rowSums(X^2)), 1e-9)) %*% X   # L2-Normierung
  sv <- irlba(X[fit_rows, ], nv = CFG$lsa_k)
  Z  <- as.matrix(X %*% sv$v)
  colnames(Z) <- sprintf("txt_lsa_%02d", seq_len(CFG$lsa_k))
  feats <- bind_cols(feats, as_tibble(Z))

  # Top-Terme pro LSA-Dimension (zur Interpretation)
  terms <- colnames(dtm)[keep]
  lsa_terms <- map_dfr(seq_len(CFG$lsa_k), function(k) tibble(
    dim           = sprintf("txt_lsa_%02d", k),
    negative_pole = paste(terms[order(sv$v[, k])][1:8], collapse = ", "),
    positive_pole = paste(terms[order(-sv$v[, k])][1:8], collapse = ", ")))
  saveRDS(lsa_terms, f_lsa)
  saveRDS(feats, f_text)
  rm(dtm, X); invisible(gc())
  log_msg("Text-Features: %d Variablen", ncol(feats) - 2)
} else {
  log_msg("Text-Features aus Cache (%s)", f_text)
}
