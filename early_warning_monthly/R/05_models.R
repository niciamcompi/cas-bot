# =============================================================================
# 05_models.R - Frühwarnmodelle mit Rolling-Origin-Evaluation (monatlich)
#
# Alle 6 Monate wird neu trainiert. Für einen Refit im Monat T werden nur Länder-Monate t
# verwendet, deren 3-Monats-Fenster t+1..t+3 vor T abgeschlossen ist (t <= T-4).
# Vorhergesagt werden die Monate T ... T+5.
#
# Methoden
#   persistence      Basisrate je nach aktueller Lage (Gewalt / Währungsstress in den letzten 3 Monaten)
#   logit            Logistische Regression mit Kernvariablen
#   enet_*           Elastic-Net-Logit: Struktur | nur News | Struktur+News
#   rf_*             Random Forest: Struktur | Struktur+News
#   gbm_*            Gradient Boosting: Struktur | Struktur+News
#   gbm_struct_long  Boosting nur Struktur, aber mit Trainingsdaten ab 2011 (ohne News-Beschränkung)
#   ensemble         Mittel aus enet_full, rf_full, gbm_full
#   rule             Faustregel: Logit mit EINER Variable (Konflikt: Tote der letzten 12 Monate,
#                    Währung: Inflation) - der ehrliche Vergleichsmassstab
#   *_zs             Foundation-Modelle zero-shot (TimesFM 3, Chronos-2, Moirai-2), ohne Training
#   fm_stack         Kalibrierte Kombination der drei Foundation-Prognosen (Logit auf Trainingsdaten)
#   *_hybrid         Elastic Net / Random Forest / Boosting mit Foundation-Prognosen als Zusatz-Features
#   ensemble_hybrid  Mittel der drei Hybrid-Modelle
# =============================================================================
P <- readRDS(file.path(DIR$proc, "panel.rds"))
STRUCT <- P$STRUCT; NEWS <- P$NEWS; FULL <- P$FULL

TARGETS <- list(
  conflict = list(y = "y_conflict", quiet = "quiet", last = P$last_ucdp,
                  state = function(d) as.numeric(d$c_deaths_3 >= log1p(CFG$conflict_thr)),
                  core = c("c_deaths_3", "c_deaths_12", "c_trend", "c_months_since", "c_region_3",
                           "s_wgi_pv", "s_log_gdp_pc", "s_log_pop", "s_infant_mort", "m_infl_yoy"),
                  rule = "c_deaths_12", fm = P$FM_C,
                  hard = function(d) coalesce(d$c_deaths_12 > 0, FALSE)),          # schwierig: etwas Gewalt
  fx = list(y = "y_fx", quiet = "fx_quiet", last = P$last_fx_month,
            state = function(d) as.numeric(d$m_fx_chg3 >= 100 * log(1 + CFG$fx_thr) / 2),
            core = c("m_fx_chg3", "m_fx_chg12", "m_fx_vol12", "m_infl_yoy", "m_infl_chg3", "m_res_chg12",
                     "m_fx_crisis12", "s_log_gdp_pc", "s_wgi_ge", "c_deaths_12"),
            rule = "m_infl_yoy", fm = P$FM_X,                                    # Inflation: klassischer Frühindikator
            hard = function(d) coalesce(d$m_fx_chg12 > 5, FALSE))               # schwierig: >5 % Abwertung in 12 M.
)

impute_fit <- function(tr, feats) {
  med <- vapply(tr[feats], function(x) { m <- median(x, na.rm = TRUE); if (is.na(m)) 0 else m }, 0)
  function(df) { for (f in feats) df[[f]][is.na(df[[f]])] <- med[[f]]; df }
}
country_folds <- function(iso, k = 5) { u <- unique(iso); f <- sample(rep_len(seq_len(k), length(u))); f[match(iso, u)] }

# Variablen ohne Varianz (z. B. fehlende Datenquelle) vorher entfernen
usable <- function(tr, feats) feats[vapply(tr[feats], \(x) isTRUE(sd(x, na.rm = TRUE) > 0), TRUE)]
fit_enet <- function(tr, feats) {
  feats <- usable(tr, feats)
  if (length(feats) < 2) { warning("Elastic Net: zu wenige variierende Variablen - verwende Basisrate"); return(list(base = mean(tr$y))) }
  fit <- cv.glmnet(as.matrix(tr[feats]), tr$y, family = "binomial", alpha = 0.5,
                   foldid = country_folds(tr$iso3c), nlambda = 50)
  fit$feats <- feats; fit
}
pred_enet <- function(fit, te, feats) {
  if (!is.null(fit$base)) return(rep(fit$base, nrow(te)))
  as.numeric(predict(fit, as.matrix(te[fit$feats]), s = "lambda.min", type = "response"))
}
fit_rf <- function(tr, feats, importance = "none") ranger(x = tr[feats], y = factor(tr$y), probability = TRUE,
  num.trees = 300, min.node.size = 25, num.threads = CFG$threads, seed = 42, importance = importance)
pred_rf <- function(fit, te, feats) predict(fit, te[feats])$predictions[, "1"]
fit_gbm <- function(tr, feats) gbm.fit(x = as.data.frame(tr[feats]), y = tr$y, distribution = "bernoulli",
  n.trees = 500, interaction.depth = 3, shrinkage = 0.03, bag.fraction = 0.7, n.minobsinnode = 30, verbose = FALSE)
pred_gbm <- function(fit, te, feats) predict(fit, as.data.frame(te[feats]), n.trees = 500, type = "response")

qlogit <- function(p) qlogis(clamp(p, 1e-3, 1 - 1e-3))
run_models <- function(tr, te, tr_long, tgt) {
  FM <- tgt$fm; HYB <- c(FULL, FM)
  # Foundation-Modelle zero-shot: Rohwahrscheinlichkeit, fehlende Werte -> Basisrate
  zshot <- setNames(lapply(FM, \(f) coalesce(te[[f]], mean(tr$y))), paste0(sub("^fm[cx]_", "", FM), "_zs"))
  imp <- impute_fit(tr_long, c(FULL, FM)); tr <- imp(tr); te <- imp(te); tr_long <- imp(tr_long)
  st_tr <- tgt$state(tr); st_te <- tgt$state(te)
  pers  <- tapply(tr$y, st_tr, mean)
  sc_mu <- vapply(tr[tgt$core], mean, 0); sc_sd <- pmax(vapply(tr[tgt$core], sd, 0), 1e-6)
  zs <- function(d) as.data.frame(scale(as.matrix(d[tgt$core]), sc_mu, sc_sd))
  lg <- suppressWarnings(glm(tr$y ~ ., family = binomial, data = zs(tr)))
  out <- list(
    persistence = unname(pers[as.character(st_te)]),
    logit       = predict(lg, zs(te), type = "response"),
    enet_struct = pred_enet(fit_enet(tr, STRUCT), te, STRUCT),
    enet_news   = pred_enet(fit_enet(tr, NEWS), te, NEWS),
    enet_full   = pred_enet(fit_enet(tr, FULL), te, FULL),
    rf_struct   = pred_rf(fit_rf(tr, STRUCT), te, STRUCT),
    rf_full     = pred_rf(fit_rf(tr, FULL), te, FULL),
    gbm_struct  = pred_gbm(fit_gbm(tr, STRUCT), te, STRUCT),
    gbm_full    = pred_gbm(fit_gbm(tr, FULL), te, FULL),
    gbm_struct_long = pred_gbm(fit_gbm(tr_long, STRUCT), te, STRUCT)
  )
  out$ensemble <- (out$enet_full + out$rf_full + out$gbm_full) / 3
  # Faustregel: eine einzige Variable
  rl <- suppressWarnings(glm(tr$y ~ tr[[tgt$rule]], family = binomial))
  out$rule <- plogis(coef(rl)[1] + coef(rl)[2] * te[[tgt$rule]])
  if (length(FM)) {
    out <- c(out, zshot)
    st <- suppressWarnings(glm(tr$y ~ ., family = binomial, data = as.data.frame(lapply(tr[FM], qlogit))))
    out$fm_stack <- unname(predict(st, as.data.frame(lapply(te[FM], qlogit)), type = "response"))
    out$enet_hybrid <- pred_enet(fit_enet(tr, HYB), te, HYB)
    out$rf_hybrid   <- pred_rf(fit_rf(tr, HYB), te, HYB)
    out$gbm_hybrid  <- pred_gbm(fit_gbm(tr, HYB), te, HYB)
    out$ensemble_hybrid <- (out$enet_hybrid + out$rf_hybrid + out$gbm_hybrid) / 3
  }
  out
}

f_pred <- file.path(DIR$proc, "oos_predictions.rds")
if (!file.exists(f_pred) || CFG$refresh) {
  preds <- imap_dfr(TARGETS, function(tgt, tname) {
    d <- P$panel |> mutate(y = .data[[tgt$y]], quiet_now = .data[[tgt$quiet]], mi = mi(month))
    last_obs <- mi(tgt$last) - CFG$horizon                  # letzter Monat mit beobachtetem Ziel
    refits <- seq(CFG$test_start, by = paste(CFG$refit_every, "months"), length.out = 100)
    refits <- refits[mi(refits) <= last_obs]
    map_dfr(refits, function(T) {
      tr      <- filter(d, !is.na(y), month >= CFG$train_start, mi <= mi(T) - CFG$horizon - 1)
      tr_long <- filter(d, !is.na(y), mi <= mi(T) - CFG$horizon - 1)
      te      <- filter(d, !is.na(y), mi >= mi(T), mi < mi(T) + CFG$refit_every, mi <= last_obs)
      if (!nrow(te)) return(NULL)
      hard_te <- tgt$hard(te)
      t0 <- Sys.time(); set.seed(mi(T))
      p  <- run_models(tr, te, tr_long, tgt)
      log_msg("  %-8s Refit %s: Train %d (lang %d), Test %d Monate x Länder, Ereignisse %d (%.0fs)", tname,
              format(T, "%Y-%m"), nrow(tr), nrow(tr_long), nrow(te), sum(te$y),
              as.numeric(difftime(Sys.time(), t0, units = "secs")))
      imap_dfr(p, \(v, m) tibble(target = tname, model = m, iso3c = te$iso3c, month = te$month,
                                  y = te$y, quiet = te$quiet_now, hard = hard_te, p_clim = mean(tr$y),
                                  p = clamp(v, 1e-5, 1 - 1e-5)))
    })
  })
  saveRDS(preds, f_pred)
} else { preds <- readRDS(f_pred); log_msg("OOS-Vorhersagen aus Cache") }

# ---------- Finale Modelle (alle Daten) -> aktuelle Beobachtungsliste ----------
final <- imap(TARGETS, function(tgt, tname) {
  d  <- P$panel |> mutate(y = .data[[tgt$y]])
  tr <- filter(d, !is.na(y), month >= CFG$train_start)
  now <- filter(d, month == max(month))          # jüngster Monat (Konfliktdaten), Makro fortgeschrieben
  if (tname == "fx") now <- filter(now, !is.na(m_fx_chg3))   # nur Länder mit aktuellen Wechselkursdaten
  FM <- tgt$fm; HYB <- c(FULL, FM)
  imp <- impute_fit(tr, HYB); tr <- imp(tr); nowi <- imp(now)
  fe <- fit_enet(tr, FULL); fr <- fit_rf(tr, FULL, importance = "permutation"); fg <- fit_gbm(tr, FULL)
  watch <- now |> select(iso3c, country, region, month) |>
    mutate(quiet = now[[tgt$quiet]],
           p_enet = pred_enet(fe, nowi, FULL), p_rf = pred_rf(fr, nowi, FULL), p_gbm = pred_gbm(fg, nowi, FULL),
           risk = (p_enet + p_rf + p_gbm) / 3)
  imp_h <- NULL
  if (length(FM)) {
    he <- fit_enet(tr, HYB); hr <- fit_rf(tr, HYB, importance = "permutation"); hg <- fit_gbm(tr, HYB)
    watch <- watch |> mutate(risk_hybrid = (pred_enet(he, nowi, HYB) + pred_rf(hr, nowi, HYB) + pred_gbm(hg, nowi, HYB)) / 3)
    for (f in FM) watch[[sub("^fm[cx]_", "p_", f)]] <- now[[f]]
    imp_h <- tibble(feature = names(hr$variable.importance), importance = hr$variable.importance) |> arrange(desc(importance))
  }
  list(
    watch = arrange(watch, desc(risk)), imp_hybrid = imp_h,
    imp_rf = tibble(feature = names(fr$variable.importance), importance = fr$variable.importance) |>
      arrange(desc(importance)))
})
saveRDS(final, file.path(DIR$proc, "final_models.rds"))
for (tname in names(final)) write.csv(final[[tname]]$watch, file.path(DIR$out, sprintf("watchlist_%s.csv", tname)), row.names = FALSE)
