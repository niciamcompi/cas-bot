# =============================================================================
# 06_evaluation.R - Bewertung als Frühwarnsystem
#   * Trennschärfe: ROC-AUC, PR-AUC (alle Länder-Monate und nur "ruhige" Länder = Ausbrüche)
#   * Kalibrierung: Brier, Brier Skill Score, Kalibrierungs-Steigung
#   * Praxis: Beobachtungsliste (Top 20 der ruhigen Länder pro Monat) -
#             wie viele Ausbrüche standen vorher darauf, und wie viele Fehlalarme gibt es?
#   * Unsicherheit: Länder-Cluster-Bootstrap (gepaart), Mehrwert der News-Daten
# =============================================================================
auc_fast <- function(y, p) { n1 <- sum(y == 1); n0 <- sum(y == 0)
  if (!n1 || !n0) return(NA_real_); (sum(rank(p)[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0) }
avg_prec <- function(y, p) { o <- order(-p); y <- y[o]; sum((cumsum(y) / seq_along(y))[y == 1]) / max(sum(y), 1) }
cal_slope <- function(y, p) unname(coef(suppressWarnings(glm(y ~ qlogis(p), family = binomial)))[2])

# Beobachtungsliste: pro Monat die k ruhigen Länder mit höchstem Risiko
watch_flags <- function(df, k = CFG$watch_k) {
  set.seed(1)
  df |> filter(quiet) |> group_by(target, model, month) |>
    mutate(on_list = rank(-p, ties.method = "random") <= k) |> ungroup()
}
# Ausbruchs-Episoden: zusammenhängende Monate (y = 1, ruhig) eines Landes = ein Ereignis
episodes <- function(wf) {
  wf |> filter(y == 1) |> arrange(target, model, iso3c, month) |>
    group_by(target, model, iso3c) |>
    mutate(ep = cumsum(c(1, diff(mi(month)) > 1))) |>
    group_by(target, model, iso3c, ep) |>
    summarise(start = min(month), warned = any(on_list),
              first_warn = if (any(on_list)) min(month[on_list]) else as.Date(NA), .groups = "drop")
}

metrics <- function(df) {
  q <- filter(df, quiet); h <- filter(df, quiet, hard)
  tibble(n = nrow(df), events = sum(df$y), auc = auc_fast(df$y, df$p), pr_auc = avg_prec(df$y, df$p),
         brier = mean((df$p - df$y)^2), bss = 1 - mean((df$p - df$y)^2) / mean((df$p_clim - df$y)^2),
         cal_slope = cal_slope(df$y, df$p),
         onset_events = sum(q$y), auc_onset = auc_fast(q$y, q$p), pr_onset = avg_prec(q$y, q$p),
         base_onset = mean(q$y), hard_events = sum(h$y), auc_hard = auc_fast(h$y, h$p))
}
res <- preds |> group_by(target, model) |> group_modify(~ metrics(.x)) |> ungroup()

wf  <- watch_flags(preds)
eps <- episodes(wf)
watch_stats <- wf |> group_by(target, model) |>
  summarise(list_precision = mean(y[on_list]), .groups = "drop") |>
  left_join(eps |> group_by(target, model) |>
              summarise(onset_episodes = n(), episodes_warned = sum(warned), .groups = "drop"),
            by = c("target", "model")) |>
  mutate(episode_recall = episodes_warned / onset_episodes)
# Lift: Trefferquote der Liste gegenüber einer Zufallsauswahl gleicher Grösse
list_share <- preds |> filter(quiet) |> distinct(target, month, iso3c) |> count(target, month) |>
  group_by(target) |> summarise(list_share = mean(pmin(CFG$watch_k / n, 1)))
watch_stats <- watch_stats |> left_join(list_share, by = "target") |> mutate(lift = episode_recall / list_share)
res <- left_join(res, watch_stats, by = c("target", "model"))

# ---------- Länder-Cluster-Bootstrap ----------
log_msg("Bootstrap (%d Replikationen) ...", CFG$n_boot)
boot <- map_dfr(names(TARGETS), function(tname) {
  w <- preds |> filter(target == tname) |> select(model, iso3c, month, y, quiet, hard, p) |>
    pivot_wider(names_from = model, values_from = p)
  mods <- setdiff(names(w), c("iso3c", "month", "y", "quiet", "hard"))
  idx <- split(seq_len(nrow(w)), w$iso3c); set.seed(7)
  map_dfr(seq_len(CFG$n_boot), function(b) {
    ii <- unlist(idx[sample(length(idx), replace = TRUE)], use.names = FALSE); x <- w[ii, ]; q <- x$quiet; h <- x$quiet & x$hard
    tibble(target = tname, b = b, model = mods,
           auc = vapply(mods, \(m) auc_fast(x$y, x[[m]]), 0),
           auc_onset = vapply(mods, \(m) auc_fast(x$y[q], x[[m]][q]), 0),
           pr_onset = vapply(mods, \(m) avg_prec(x$y[q], x[[m]][q]), 0),
           auc_hard = vapply(mods, \(m) auc_fast(x$y[h], x[[m]][h]), 0))
  })
})
ci <- boot |> group_by(target, model) |>
  summarise(auc_lo = quantile(auc, .025, na.rm = TRUE), auc_hi = quantile(auc, .975, na.rm = TRUE),
            onset_lo = quantile(auc_onset, .025, na.rm = TRUE), onset_hi = quantile(auc_onset, .975, na.rm = TRUE),
            hard_lo = quantile(auc_hard, .025, na.rm = TRUE), hard_hi = quantile(auc_hard, .975, na.rm = TRUE),
            .groups = "drop")
res <- left_join(res, ci, by = c("target", "model"))

# Mehrwert einzelner Bausteine, gepaart im Bootstrap:
#   News:       (Struktur+News) - Struktur
#   Foundation: Hybrid (Struktur+News+Foundation) - (Struktur+News)
#   Gegen Faustregel: bestes Ensemble - Faustregel
NEWS_METRICS <- c(auc_onset = "AUC Ausbrüche", auc_hard = "AUC schwierige Fälle", pr_onset = "PR-AUC Ausbrüche")
COMPARISONS <- tribble(
  ~block,         ~method,        ~with,             ~without,
  "News",         "Elastic Net",  "enet_full",       "enet_struct",
  "News",         "Random Forest","rf_full",         "rf_struct",
  "News",         "Boosting",     "gbm_full",        "gbm_struct",
  "Foundation",   "Elastic Net",  "enet_hybrid",     "enet_full",
  "Foundation",   "Random Forest","rf_hybrid",       "rf_full",
  "Foundation",   "Boosting",     "gbm_hybrid",      "gbm_full",
  "Foundation",   "Ensemble",     "ensemble_hybrid", "ensemble",
  "ML vs. Faustregel", "Ensemble", "ensemble",       "rule",
  "Foundation vs. Faustregel", "Foundation-Stack", "fm_stack", "rule")
gains <- map_dfr(names(TARGETS), \(tname) pmap_dfr(COMPARISONS, function(block, method, with, without) {
  if (!all(c(with, without) %in% boot$model[boot$target == tname])) return(NULL)
  map_dfr(names(NEWS_METRICS), function(k) {
    d <- boot |> filter(target == tname, model %in% c(with, without)) |>
      select(b, model, v = all_of(k)) |> pivot_wider(names_from = model, values_from = v)
    dd <- d[[with]] - d[[without]]; r <- filter(res, target == tname)
    tibble(target = tname, block = block, method = method, metric = NEWS_METRICS[[k]],
           delta = r[[k]][r$model == with] - r[[k]][r$model == without],
           lo = quantile(dd, .025, na.rm = TRUE), hi = quantile(dd, .975, na.rm = TRUE), p_gt0 = mean(dd > 0, na.rm = TRUE))
  })
}))
news_gain <- filter(gains, block == "News")

# Ranking pro Ziel: Fokus Frühwarnung (Ausbrüche) + Kalibrierung
res <- res |> group_by(target) |>
  mutate(score = (rank(-auc_onset) + rank(-auc_hard) + rank(-pr_onset) + rank(-episode_recall) + rank(-auc) +
                    rank(brier) + rank(abs(cal_slope - 1))) / 7,
         rank = rank(score, ties.method = "min")) |> ungroup() |> arrange(target, rank)

by_half <- preds |> mutate(half = as.Date(paste0(format(month, "%Y-"), ifelse(as.integer(format(month, "%m")) <= 6, "01", "07"), "-01"))) |>
  group_by(target, model, half) |>
  summarise(auc = auc_fast(y, p), auc_onset = auc_fast(y[quiet], p[quiet]), .groups = "drop")

write.csv(res, file.path(DIR$out, "model_evaluation.csv"), row.names = FALSE)
write.csv(gains, file.path(DIR$out, "value_added.csv"), row.names = FALSE)
