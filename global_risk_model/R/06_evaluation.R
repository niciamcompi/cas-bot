# =============================================================================
# 06_evaluation.R - Bewertung der Methoden
#   Diskriminierung: ROC-AUC, PR-AUC (Average Precision), AUC für Krisen-Ausbrüche
#                    (ohne COVID-Schock 2020) und speziell für Konflikt-Ausbrüche
#   Kalibrierung:    Brier Score, Brier Skill Score, Log-Loss, Kalibrierungs-Steigung
#   Praxis:          Recall / Precision der Top-10 %-Warnliste pro Jahr
#   Unsicherheit:    Cluster-Bootstrap nach Land, DeLong-Test vs. Logit
# =============================================================================

auc_fast <- function(y, p) {
  n1 <- sum(y == 1); n0 <- sum(y == 0)
  if (n1 == 0 || n0 == 0) return(NA_real_)
  (sum(rank(p)[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}
avg_precision <- function(y, p) {
  o <- order(-p); y <- y[o]; tp <- cumsum(y); sum((tp / seq_along(y))[y == 1]) / max(sum(y), 1)
}
cal_slope <- function(y, p) unname(coef(suppressWarnings(glm(y ~ qlogis(p), family = binomial)))[2])
top_decile <- function(df) {
  # genau 10 % pro Jahr markieren; Gleichstände zufällig brechen (fair für Modelle mit wenigen Werten)
  set.seed(99)
  df |> group_by(year) |> mutate(flag = rank(-p, ties.method = "random") <= ceiling(0.1 * n())) |> ungroup() |>
    summarise(recall = sum(flag & y == 1) / sum(y == 1), precision = sum(flag & y == 1) / sum(flag))
}

COVID_YEAR <- 2019   # Feature-Jahr, dessen Ereignisjahr 2020 der globale Pandemie-Schock ist
onset_idx  <- function(df) df$crisis_now == 0 & df$year != COVID_YEAR
conf_onset <- function(df) {
  yc <- coalesce(df$y_conflict, 0); i <- df$crisis_now == 0 & (df$y == 0 | yc == 1)
  list(y = yc[i], i = i)
}

metrics <- function(df) {
  td <- top_decile(df); on <- df[onset_idx(df), ]; co <- conf_onset(df)
  tibble(
    n = nrow(df), events = sum(df$y),
    auc = auc_fast(df$y, df$p),
    pr_auc = avg_precision(df$y, df$p),
    auc_onset = auc_fast(on$y, on$p),
    auc_conflict_onset = auc_fast(co$y, df$p[co$i]),
    brier = mean((df$p - df$y)^2),
    bss = 1 - mean((df$p - df$y)^2) / mean((df$p_clim - df$y)^2),
    logloss = -mean(df$y * log(df$p) + (1 - df$y) * log(1 - df$p)),
    cal_slope = cal_slope(df$y, df$p),
    top10_recall = td$recall, top10_precision = td$precision
  )
}

MODEL_LABELS <- c(
  persistence = "Persistenz (naiv)", inform_index = "INFORM-Index (Experte)",
  pca_index = "PCA-Index", logit = "Logit (10 Kernvariablen)", gam = "GAM (Splines)",
  enet_struct = "Elastic Net - Struktur", enet_text = "Elastic Net - nur Text",
  enet_full = "Elastic Net - Struktur+Text", rf_struct = "Random Forest - Struktur",
  rf_full = "Random Forest - Struktur+Text", gbm_struct = "Boosting - Struktur",
  gbm_full = "Boosting - Struktur+Text", ensemble = "Ensemble (EN+RF+GBM)")
MODEL_FAMILY <- c(
  persistence = "Benchmark", inform_index = "Index", pca_index = "Index", logit = "Statistisch",
  gam = "Statistisch", enet_struct = "Regularisiert", enet_text = "Regularisiert",
  enet_full = "Regularisiert", rf_struct = "Machine Learning", rf_full = "Machine Learning",
  gbm_struct = "Machine Learning", gbm_full = "Machine Learning", ensemble = "Ensemble")
FAMILY_COL <- c(Benchmark = "#8a8984", Index = PAL[["orange"]], Statistisch = PAL[["aqua"]],
                Regularisiert = PAL[["blue"]], `Machine Learning` = PAL[["violet"]],
                Ensemble = PAL[["red"]])

# ---------- Punktschätzer ----------
res <- preds |> group_by(model) |> group_modify(~ metrics(.x)) |> ungroup()

# ---------- Cluster-Bootstrap (gepaart über Modelle, Resampling ganzer Länder) ----------
log_msg("Cluster-Bootstrap (%d Replikationen) ...", CFG$n_boot)
wide <- preds |> select(model, iso3c, year, y, y_conflict, crisis_now, p) |>
  pivot_wider(names_from = model, values_from = p)
mods <- unique(preds$model)
idx_by_country <- split(seq_len(nrow(wide)), wide$iso3c)
set.seed(7)
boot <- map_dfr(seq_len(CFG$n_boot), function(b) {
  ii <- unlist(idx_by_country[sample(length(idx_by_country), replace = TRUE)], use.names = FALSE)
  w <- wide[ii, ]; on <- onset_idx(w); co <- conf_onset(w)
  tibble(b = b, model = mods,
         auc = vapply(mods, \(m) auc_fast(w$y, w[[m]]), 0),
         brier = vapply(mods, \(m) mean((w[[m]] - w$y)^2), 0),
         auc_onset = vapply(mods, \(m) auc_fast(w$y[on], w[[m]][on]), 0),
         auc_conflict_onset = vapply(mods, \(m) auc_fast(co$y, w[[m]][co$i]), 0))
})
ci <- boot |> group_by(model) |>
  summarise(auc_lo = quantile(auc, .025), auc_hi = quantile(auc, .975),
            brier_lo = quantile(brier, .025), brier_hi = quantile(brier, .975),
            onset_lo = quantile(auc_onset, .025, na.rm = TRUE), onset_hi = quantile(auc_onset, .975, na.rm = TRUE))
res <- left_join(res, ci, by = "model")

# Mehrwert der Textdaten: Delta-AUC (Struktur+Text minus Struktur), gepaart
GAIN_METRICS <- c(auc = "AUC (alle)", auc_onset = "AUC Ausbrüche (ohne 2020)",
                  auc_conflict_onset = "AUC Konflikt-Ausbrüche")
text_gain <- map_dfr(c("enet", "rf", "gbm"), function(m) map_dfr(names(GAIN_METRICS), function(k) {
  d <- boot |> filter(model %in% paste0(m, c("_full", "_struct"))) |>
    select(b, model, v = all_of(k)) |> pivot_wider(names_from = model, values_from = v)
  dd <- d[[paste0(m, "_full")]] - d[[paste0(m, "_struct")]]
  tibble(method = m, metric = GAIN_METRICS[[k]],
         delta = res[[k]][res$model == paste0(m, "_full")] - res[[k]][res$model == paste0(m, "_struct")],
         lo = quantile(dd, .025, na.rm = TRUE), hi = quantile(dd, .975, na.rm = TRUE),
         p_gt0 = mean(dd > 0, na.rm = TRUE))
}))

# DeLong-Test gegen das klassische Logit
delong <- map_dfr(setdiff(mods, "logit"), function(m) {
  r1 <- roc(wide$y, wide[[m]], quiet = TRUE, direction = "<")
  r0 <- roc(wide$y, wide$logit, quiet = TRUE, direction = "<")
  tibble(model = m, delong_p_vs_logit = roc.test(r1, r0, method = "delong", paired = TRUE)$p.value)
})
res <- left_join(res, delong, by = "model")

# Multikriterien-Ranking
res <- res |>
  mutate(r_auc = rank(-auc), r_pr = rank(-pr_auc), r_onset = rank(-auc_onset),
         r_conf = rank(-auc_conflict_onset), r_brier = rank(brier), r_cal = rank(abs(cal_slope - 1)), r_top = rank(-top10_recall),
         score_rank = (r_auc + r_pr + r_onset + r_conf + r_brier + r_cal + r_top) / 7,
         overall_rank = rank(score_rank, ties.method = "min"),
         label = MODEL_LABELS[model], family = MODEL_FAMILY[model]) |>
  arrange(overall_rank)

# Teilaufgaben: Konflikt vs. Makro (jeweils gegen Nicht-Krisen)
by_type <- preds |> mutate(yc = coalesce(y_conflict, 0), ym = coalesce(y_macro, 0)) |>
  group_by(model) |>
  summarise(auc_conflict = auc_fast(yc[y == 0 | yc == 1], p[y == 0 | yc == 1]),
            auc_macro    = auc_fast(ym[y == 0 | ym == 1], p[y == 0 | ym == 1]))
by_year <- preds |> group_by(model, year) |>
  summarise(auc = auc_fast(y, p), brier = mean((p - y)^2), rate = mean(y), .groups = "drop")

write.csv(select(res, -starts_with("r_")), file.path(DIR$out, "model_evaluation.csv"), row.names = FALSE)
write.csv(text_gain, file.path(DIR$out, "text_value_added.csv"), row.names = FALSE)
write.csv(by_type, file.path(DIR$out, "auc_by_crisis_type.csv"), row.names = FALSE)
write.csv(by_year, file.path(DIR$out, "auc_by_year.csv"), row.names = FALSE)
