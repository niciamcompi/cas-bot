# =============================================================================
# 07_report.R - Grafiken und Markdown-Bericht
# =============================================================================
FM <- readRDS(file.path(DIR$proc, "final_models.rds"))
lab <- function(m) factor(MODEL_LABELS[m], levels = rev(MODEL_LABELS[res$model]))
cap <- "Quelle: World Bank WDI/WGI, UCDP (via WDI), UN General Debate Corpus. Out-of-sample, Rolling Origin."

# 1) Leistungsübersicht: AUC mit 95%-KI und Brier Skill Score
p1 <- ggplot(res, aes(y = lab(model), colour = family)) +
  geom_segment(aes(x = auc_lo, xend = auc_hi, yend = lab(model)), linewidth = 0.9, alpha = 0.6) +
  geom_point(aes(x = auc), size = 2.8) +
  scale_colour_manual(values = FAMILY_COL) +
  labs(x = "ROC-AUC (95 %-KI, Länder-Bootstrap)", y = NULL, title = "Trennschärfe") + theme_risk()
p2 <- ggplot(res, aes(y = lab(model), x = bss, fill = family)) +
  geom_col(width = 0.6) + geom_vline(xintercept = 0, colour = INK$secondary, linewidth = 0.3) +
  scale_fill_manual(values = FAMILY_COL, guide = "none") +
  labs(x = "Brier Skill Score (vs. Basisrate)", y = NULL, title = "Kalibrierte Treffsicherheit") +
  theme_risk() + theme(axis.text.y = element_blank())
save_fig((p1 | p2) + plot_layout(widths = c(1.4, 1), guides = "collect") &
           theme(legend.position = "bottom"),
         "01_model_performance.png", w = 11, h = 6)

# 2) ROC-Kurven ausgewählter Modelle
sel <- c("persistence", "inform_index", "logit", "enet_full", "rf_full", "ensemble")
sel_col <- setNames(unname(PAL[c("blue", "orange", "aqua", "yellow", "violet", "red")]), MODEL_LABELS[sel])
roc_df <- preds |> filter(model %in% sel) |> group_by(model) |>
  group_modify(~ { r <- roc(.x$y, .x$p, quiet = TRUE, direction = "<")
                   tibble(fpr = 1 - r$specificities, tpr = r$sensitivities) }) |>
  ungroup() |> mutate(label = factor(MODEL_LABELS[model], levels = MODEL_LABELS[sel]))
save_fig(ggplot(roc_df, aes(fpr, tpr, colour = label)) +
  geom_abline(linetype = 2, colour = INK$grid) + geom_line(linewidth = 0.7) +
  scale_colour_manual(values = sel_col) + coord_equal() +
  guides(colour = guide_legend(nrow = 2)) +
  labs(x = "Falsch-Positiv-Rate", y = "Richtig-Positiv-Rate",
       title = "ROC-Kurven (Out-of-sample)", caption = cap) + theme_risk(), "02_roc_curves.png", 8, 8)

# 3) Kalibrierungsdiagramm (Dezile)
cal <- preds |> filter(model %in% sel) |> group_by(model) |>
  mutate(bin = ntile(p, 10)) |> group_by(model, bin) |>
  summarise(p = mean(p), obs = mean(y), n = n(), .groups = "drop") |>
  mutate(label = factor(MODEL_LABELS[model], levels = MODEL_LABELS[sel]))
save_fig(ggplot(cal, aes(p, obs)) +
  geom_abline(linetype = 2, colour = INK$secondary) +
  geom_line(colour = PAL[["blue"]], linewidth = 0.7) + geom_point(colour = PAL[["blue"]], size = 2) +
  facet_wrap(~label, ncol = 3) + coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
  labs(x = "Vorhergesagte Wahrscheinlichkeit", y = "Beobachtete Krisenrate",
       title = "Kalibrierung: Prognose vs. Realität (Dezile)", caption = cap) + theme_risk(),
  "03_calibration.png", 10, 7.5)

# 4) AUC pro Testjahr
yr_sel <- c("logit", "enet_full", "rf_full", "ensemble")
save_fig(ggplot(filter(by_year, model %in% yr_sel),
                aes(year, auc, colour = factor(MODEL_LABELS[model], levels = MODEL_LABELS[yr_sel]))) +
  geom_line(linewidth = 0.7) + geom_point(size = 2) +
  scale_colour_manual(values = unname(PAL[c("aqua", "yellow", "violet", "red")])) +
  labs(x = "Prognosejahr t (Ereignis in t+1)", y = "ROC-AUC", title = "Stabilität über die Zeit",
       subtitle = "Strukturbrüche (z. B. Pandemie 2020) zeigen sich als Einbrüche", caption = cap) +
  theme_risk(), "04_auc_by_year.png", 9, 5)

# 5) Mehrwert der Textdaten
tg <- text_gain |> mutate(method = c(enet = "Elastic Net", rf = "Random Forest", gbm = "Boosting")[method],
                          metric = factor(metric, levels = unname(GAIN_METRICS)))
save_fig(ggplot(tg, aes(x = delta, y = method)) +
  geom_vline(xintercept = 0, colour = INK$secondary, linewidth = 0.3) +
  geom_segment(aes(x = lo, xend = hi, yend = method), colour = PAL[["blue"]], linewidth = 0.9, alpha = 0.6) +
  geom_point(colour = PAL[["blue"]], size = 3) + facet_wrap(~metric) +
  labs(x = "Delta AUC: Struktur+Text minus Struktur (95 %-KI)", y = NULL,
       title = "Was bringen die UN-Reden?", caption = cap) + theme_risk(), "05_text_value_added.png", 11, 4)

# 6) Wichtigste Treiber
top_rf <- head(FM$imp_rf, 20) |> mutate(type = ifelse(grepl("^txt_", feature), "Text", "Strukturiert"))
top_en <- head(FM$imp_enet, 20) |> mutate(type = ifelse(grepl("^txt_", feature), "Text", "Strukturiert"))
tcol <- c(Strukturiert = PAL[["blue"]], Text = PAL[["orange"]])
q1 <- ggplot(top_rf, aes(importance, reorder(feature, importance), fill = type)) + geom_col(width = 0.65) +
  scale_fill_manual(values = tcol, limits = names(tcol), drop = FALSE) + labs(x = "Permutations-Wichtigkeit", y = NULL, title = "Random Forest") + theme_risk()
q2 <- ggplot(top_en, aes(coef_std, reorder(feature, abs(coef_std)), fill = type)) + geom_col(width = 0.65) +
  scale_fill_manual(values = tcol, limits = names(tcol), drop = FALSE) + labs(x = "Standardisierter Koeffizient (Log-Odds)", y = NULL,
  title = "Elastic Net") + theme_risk()
save_fig((q1 | q2) + plot_layout(guides = "collect") & theme(legend.position = "bottom"),
         "06_drivers.png", 12, 6.5)

# 7) Globaler Text-Risikoindikator vs. Krisenrate (zwei Panels, gemeinsame Zeitachse)
gl <- P$panel |> filter(year <= P$last_conflict_year, year >= 1991) |>
  group_by(year) |>
  summarise(`Konflikt-Vokabular (pro 1000 Wörter)` = mean(txt_lex_conflict[txt_has_speech == 1], na.rm = TRUE),
            `Wirtschaftsstress-Vokabular (pro 1000 Wörter)` = mean(txt_lex_econ_stress[txt_has_speech == 1], na.rm = TRUE),
            `Anteil Länder in Krise (%)` = 100 * mean(crisis_now)) |>
  pivot_longer(-year)
save_fig(ggplot(gl, aes(year, value)) + geom_line(colour = PAL[["blue"]], linewidth = 0.7) +
  facet_wrap(~name, ncol = 1, scales = "free_y") +
  labs(x = NULL, y = NULL, title = "Globale Risikolage: Sprache der UN-Generaldebatte und reale Krisen",
       caption = cap) + theme_risk(), "07_global_text_risk.png", 9, 7.5)

# 8) Prognose: zwei Listen - akute Krisenländer und Frühwarnung (derzeit keine erfasste Krise)
fy <- P$last_feature_year + 1
fc_plot <- bind_rows(
  FM$forecast |> filter(crisis_now == 1) |> head(15) |> mutate(group = "Anhaltende Krise: Top 15"),
  FM$forecast |> filter(crisis_now == 0) |> head(15) |> mutate(group = "Frühwarnung: Top 15 ohne erfasste Krise")) |>
  mutate(country = tidytext::reorder_within(country, risk, group))
save_fig(ggplot(fc_plot, aes(100 * risk, country, fill = group)) + geom_col(width = 0.65) +
  geom_text(aes(label = sprintf("%.0f", 100 * risk)), hjust = -0.2, size = 3, colour = INK$secondary) +
  tidytext::scale_y_reordered() + facet_wrap(~group, scales = "free_y", ncol = 2) +
  scale_fill_manual(values = c(PAL[["red"]], PAL[["blue"]]), guide = "none") +
  scale_x_continuous(limits = c(0, 105), expand = c(0, 0)) +
  labs(x = sprintf("Krisenwahrscheinlichkeit %d (%%, Ensemble)", fy), y = NULL,
       title = sprintf("Global Risk Forecast %d", fy),
       caption = sprintf("Basis: Daten %d. Konfliktstatus %d aus %d fortgeschrieben. 'Ohne erfasste Krise' kann auch Datenlücken bedeuten.",
                         P$last_feature_year, P$last_feature_year, P$last_conflict_year)) +
  theme_risk(), "08_forecast.png", 12, 6.5)

# Aufsteiger: höchstes Risiko unter Ländern ohne aktuelle Krise
emerging <- FM$forecast |> filter(crisis_now == 0) |> head(15)

# ---------- Markdown-Bericht ----------
md_table <- function(df, digits = 3) {
  fmt <- function(x) {
    if (all(is.na(x) | x == round(x))) return(ifelse(is.na(x), "-", format(x)))
    ifelse(is.na(x), "-", ifelse(abs(x) < 0.001 & x != 0 & x > 0, "<0.001", formatC(x, digits = digits, format = "f")))
  }
  df <- mutate(df, across(where(is.numeric), fmt))
  c(paste0("| ", paste(names(df), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"),
    apply(df, 1, \(r) paste0("| ", paste(r, collapse = " | "), " |")))
}
lsa <- readRDS(f_lsa)
tab_main <- res |> transmute(Rang = overall_rank, Methode = label, AUC = auc,
  `AUC 95%-KI` = sprintf("%.3f-%.3f", auc_lo, auc_hi), `PR-AUC` = pr_auc,
  `AUC Ausbrüche*` = auc_onset, `AUC Konflikt-Ausbr.` = auc_conflict_onset, Brier = brier, BSS = bss, `Kal.-Steigung` = cal_slope,
  `Top-10%-Recall` = top10_recall, `DeLong p vs. Logit` = delong_p_vs_logit)
best <- res$model[1]

report <- c(
  "# Global Risk Model - automatischer Evaluationsbericht", "",
  sprintf("_Erzeugt am %s. Alle Kennzahlen sind echte Out-of-sample-Werte._", format(Sys.Date(), "%d.%m.%Y")), "",
  "## Datengrundlage", "",
  sprintf("* Länder-Jahre im Modell: **%d** (%d Länder, %d-%d), Krisenrate %.1f %%",
          nrow(md), n_distinct(md$iso3c), min(md$year), max(md$year), 100 * mean(md$y)),
  sprintf("* Out-of-sample-Testjahre: %d-%d (Ereignisse %d-%d), %d Vorhersagen pro Methode",
          min(test_years), max(test_years), min(test_years) + 1, max(test_years) + 1,
          sum(preds$model == "logit")),
  sprintf("* Strukturierte Features: %d, Text-Features: %d", length(STRUCT), length(TEXT)), "",
  "## Methodenvergleich", "", md_table(tab_main), "",
  "_Rang = Mittel der Ränge aus AUC, PR-AUC, AUC Ausbrüche, AUC Konflikt-Ausbrüche, Brier, |Kalibrierungs-Steigung - 1| und Top-10%-Recall. * Ausbrüche = Länder ohne aktuelle Krise; ohne das Pandemie-Ereignisjahr 2020, das mit rund der Hälfte aller Ausbrüche jede länderspezifische Bewertung dominieren würde._", "",
  "![Leistung](figures/01_model_performance.png)", "",
  "## Teilaufgaben: Konflikt vs. Makrokrise", "",
  md_table(by_type |> mutate(Methode = MODEL_LABELS[model]) |> select(Methode, `AUC Konflikt` = auc_conflict, `AUC Makro` = auc_macro)), "",
  "## Mehrwert der Textdaten", "",
  md_table(tg |> transmute(Methode = method, Metrik = metric, `Delta AUC` = delta,
                           `KI unten` = lo, `KI oben` = hi, `P(Delta>0)` = p_gt0)), "",
  "![Text](figures/05_text_value_added.png)", "",
  "### Interpretation der LSA-Textdimensionen", "", md_table(lsa), "",
  "## Diagnostik", "", "![ROC](figures/02_roc_curves.png)", "", "![Kalibrierung](figures/03_calibration.png)", "",
  "![Zeit](figures/04_auc_by_year.png)", "", "![Treiber](figures/06_drivers.png)", "",
  "![Global](figures/07_global_text_risk.png)", "",
  sprintf("## Prognose %d", fy), "", "![Forecast](figures/08_forecast.png)", "",
  "### Höchstes Risiko unter Ländern ohne aktuelle Krise (Frühwarnung)", "",
  md_table(emerging |> transmute(Land = country, Region = region,
                                 `Risiko (Ensemble)` = risk, `Elastic Net` = p_enet,
                                 `Random Forest` = p_rf, Boosting = p_gbm, `INFORM-Index` = p_inform))
)
writeLines(report, file.path(DIR$out, "report.md"))
log_msg("Bericht geschrieben: %s", file.path(DIR$out, "report.md"))
