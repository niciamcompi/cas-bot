# =============================================================================
# 05_models.R - Methodenvergleich mit Rolling-Origin-Evaluation (expandierendes Fenster)
#
# Für jedes Testjahr T: Training auf allen Länder-Jahren t <= T-1 (deren Ergebnis t+1 <= T
# zum Zeitpunkt T bekannt ist), Vorhersage für Jahr T. Keine Information aus der Zukunft.
#
# Methoden:
#   persistence   Naive Benchmark: P(Krise | Krise heute) aus dem Training
#   inform_index  Experten-Composite-Index (INFORM-Logik: Hazard x Vulnerabilität x Coping)
#   pca_index     Datengetriebener Index (1. Hauptkomponente)
#   logit         Klassische logistische Regression, 10 Kernvariablen
#   gam           Generalisiertes additives Modell (nichtlineare Splines)
#   enet_struct   Elastic-Net-Logit, nur strukturierte Daten
#   enet_text     Elastic-Net-Logit, nur Textdaten
#   enet_full     Elastic-Net-Logit, Struktur + Text
#   rf_struct/full    Random Forest (ranger)
#   gbm_struct/full   Gradient Boosting (gbm)
#   ensemble      Mittelwert aus enet_full, rf_full, gbm_full
# =============================================================================

P <- readRDS(file.path(DIR$proc, "panel.rds"))
md <- P$model_df; STRUCT <- P$STRUCT; TEXT <- P$TEXT; FULL <- P$FULL

CORE <- c("crisis_now", "deaths_log", "gdp_growth", "inflation_slog", "log_gdp_pc",
          "wgi_pv", "years_since_crisis", "regional_crisis_share", "fx_change", "infant_mortality")

INFORM_DIMS <- list(
  hazard        = c(deaths_log = 1, crisis_count_5y = 1, inflation_slog = 1, gdp_growth = -1,
                    fx_change = 1, regional_crisis_share = 1),
  vulnerability = c(log_gdp_pc = -1, infant_mortality = 1, pop_0014 = 1, oda_gni = 1,
                    unemployment = 1, ext_debt_gni = 1),
  coping        = c(wgi_pv = -1, wgi_ge = -1, wgi_rl = -1, wgi_cc = -1, reserves_months = -1)
)

# ---------- Vorverarbeitung (nur mit Trainingsstatistiken) ----------
impute_fit <- function(tr, feats) {
  med <- vapply(tr[feats], function(x) { m <- median(x[is.finite(x)]); if (is.na(m)) 0 else m }, 0)
  function(df) { for (f in feats) { x <- df[[f]]; x[!is.finite(x)] <- med[[f]]; df[[f]] <- x }; df }
}
scale_fit <- function(tr, feats) {
  mu <- vapply(tr[feats], mean, 0); s <- vapply(tr[feats], sd, 0); s[!is.finite(s) | s == 0] <- 1
  function(df) sweep(sweep(as.matrix(df[feats]), 2, mu), 2, s, "/")
}
calibrate <- function(score_tr, y_tr, score_te) {
  fit <- suppressWarnings(glm(y ~ s, family = binomial, data = data.frame(y = y_tr, s = score_tr)))
  predict(fit, data.frame(s = score_te), type = "response")
}
country_folds <- function(iso, k = 5) {
  u <- unique(iso); f <- sample(rep_len(seq_len(k), length(u))); f[match(iso, u)]
}

# ---------- Modelle: function(tr, te) -> Wahrscheinlichkeiten für te ----------
inform_score <- function(tr, df) {
  dims <- lapply(INFORM_DIMS, function(d) {
    s <- sapply(names(d), function(v) {
      lo <- quantile(d[[v]] * tr[[v]], 0.02); hi <- quantile(d[[v]] * tr[[v]], 0.98)
      10 * clamp((d[[v]] * df[[v]] - lo) / max(hi - lo, 1e-9), 0, 1)
    })
    rowMeans(s)
  })
  ((dims$hazard + 0.1) * (dims$vulnerability + 0.1) * (dims$coping + 0.1))^(1 / 3)
}

MODELS <- list(
  persistence = function(tr, te) {
    r <- tapply(tr$y, tr$crisis_now, mean); unname(r[as.character(te$crisis_now)])
  },
  inform_index = function(tr, te) calibrate(inform_score(tr, tr), tr$y, inform_score(tr, te)),
  pca_index = function(tr, te) {
    sc <- scale_fit(tr, STRUCT); pc <- prcomp(sc(tr))
    s_tr <- pc$x[, 1]; sgn <- sign(cor(s_tr, tr$y))
    calibrate(sgn * s_tr, tr$y, sgn * predict(pc, sc(te))[, 1])
  },
  logit = function(tr, te) {
    sc <- scale_fit(tr, CORE)
    fit <- suppressWarnings(glm(tr$y ~ ., family = binomial, data = as.data.frame(sc(tr))))
    predict(fit, as.data.frame(sc(te)), type = "response")
  },
  gam = function(tr, te) {
    f <- y ~ crisis_now + conflict_now + s(deaths_log, k = 5) + s(gdp_growth, k = 5) +
      s(inflation_slog, k = 5) + s(log_gdp_pc, k = 5) + s(wgi_pv, k = 5) +
      s(years_since_crisis, k = 5) + s(regional_crisis_share, k = 5) + s(fx_change, k = 5)
    fit <- gam(f, family = binomial, data = tr, method = "REML")
    as.numeric(predict(fit, te, type = "response"))
  },
  enet_struct = function(tr, te) enet(tr, te, STRUCT),
  enet_text   = function(tr, te) enet(tr, te, TEXT),
  enet_full   = function(tr, te) enet(tr, te, FULL),
  rf_struct   = function(tr, te) rf(tr, te, STRUCT),
  rf_full     = function(tr, te) rf(tr, te, FULL),
  gbm_struct  = function(tr, te) gb(tr, te, STRUCT),
  gbm_full    = function(tr, te) gb(tr, te, FULL)
)

enet <- function(tr, te, feats, return_fit = FALSE) {
  cv <- cv.glmnet(as.matrix(tr[feats]), tr$y, family = "binomial", alpha = 0.5,
                  foldid = country_folds(tr$iso3c), type.measure = "deviance")
  if (return_fit) return(cv)
  as.numeric(predict(cv, as.matrix(te[feats]), s = "lambda.min", type = "response"))
}
rf <- function(tr, te, feats, return_fit = FALSE, importance = "none") {
  fit <- ranger(x = tr[feats], y = factor(tr$y), probability = TRUE, num.trees = 500,
                min.node.size = 10, num.threads = CFG$threads, seed = 42, importance = importance)
  if (return_fit) return(fit)
  predict(fit, te[feats])$predictions[, "1"]
}
gb <- function(tr, te, feats, return_fit = FALSE) {
  fit <- gbm.fit(x = as.data.frame(tr[feats]), y = tr$y, distribution = "bernoulli",
                 n.trees = 600, interaction.depth = 3, shrinkage = 0.02, bag.fraction = 0.7,
                 n.minobsinnode = 20, verbose = FALSE)
  if (return_fit) return(fit)
  predict(fit, as.data.frame(te[feats]), n.trees = 600, type = "response")
}

# ---------- Rolling-Origin-Loop ----------
f_pred <- file.path(DIR$proc, "oos_predictions.rds")
test_years <- CFG$first_test_year:max(md$year)

if (!file.exists(f_pred) || CFG$refresh) {
  preds <- map_dfr(test_years, function(T) {
    tr <- filter(md, year <= T - 1); te <- filter(md, year == T)
    imp <- impute_fit(tr, FULL); tr <- imp(tr); te <- imp(te)
    t0 <- Sys.time()
    out <- imap_dfr(MODELS, function(fn, nm) {
      set.seed(T)
      tibble(model = nm, iso3c = te$iso3c, year = T, y = te$y, y_conflict = te$y_conflict,
             y_macro = te$y_macro, crisis_now = te$crisis_now, p_clim = mean(tr$y),
             p = clamp(fn(tr, te), 1e-4, 1 - 1e-4))
    })
    log_msg("Testjahr %d: Train n=%d, Test n=%d, Krisen=%d (%.0fs)", T, nrow(tr), nrow(te),
            sum(te$y), as.numeric(difftime(Sys.time(), t0, units = "secs")))
    out
  })
  ens <- preds |> filter(model %in% c("enet_full", "rf_full", "gbm_full")) |>
    group_by(iso3c, year, y, y_conflict, y_macro, crisis_now, p_clim) |>
    summarise(p = mean(p), .groups = "drop") |> mutate(model = "ensemble")
  preds <- bind_rows(preds, ens)
  saveRDS(preds, f_pred)
} else {
  preds <- readRDS(f_pred)
  log_msg("OOS-Vorhersagen aus Cache (%s)", f_pred)
}

# ---------- Finale Modelle auf allen Daten: Prognose + Interpretation ----------
log_msg("Fitte finale Modelle auf allen %d Beobachtungen ...", nrow(md))
imp_all <- impute_fit(md, FULL); md_i <- imp_all(md); fc_i <- imp_all(P$forecast_df)
set.seed(1)
fit_rf   <- rf(md_i, NULL, FULL, return_fit = TRUE, importance = "permutation")
fit_enet <- enet(md_i, NULL, FULL, return_fit = TRUE)
fit_gbm  <- gb(md_i, NULL, FULL, return_fit = TRUE)

forecast <- P$forecast_df |>
  select(iso3c, country, region, income, year) |>
  mutate(p_enet = as.numeric(predict(fit_enet, as.matrix(fc_i[FULL]), s = "lambda.min", type = "response")),
         p_rf   = predict(fit_rf, fc_i[FULL])$predictions[, "1"],
         p_gbm  = predict(fit_gbm, as.data.frame(fc_i[FULL]), n.trees = 600, type = "response"),
         p_inform = calibrate(inform_score(md_i, md_i), md_i$y, inform_score(md_i, fc_i)),
         risk = (p_enet + p_rf + p_gbm) / 3,
         forecast_year = year + 1,
         crisis_now = fc_i$crisis_now) |>
  arrange(desc(risk))

imp_rf <- tibble(feature = names(fit_rf$variable.importance),
                 importance = fit_rf$variable.importance) |> arrange(desc(importance))
cf <- coef(fit_enet, s = "lambda.min")
imp_enet <- tibble(feature = rownames(cf), coef = as.numeric(cf)) |>
  filter(feature != "(Intercept)", coef != 0) |>
  mutate(coef_std = coef * vapply(md_i[feature], sd, 0)) |> arrange(desc(abs(coef_std)))

saveRDS(list(forecast = forecast, imp_rf = imp_rf, imp_enet = imp_enet),
        file.path(DIR$proc, "final_models.rds"))
write.csv(forecast, file.path(DIR$out, sprintf("forecast_%d.csv", P$last_feature_year + 1)), row.names = FALSE)
