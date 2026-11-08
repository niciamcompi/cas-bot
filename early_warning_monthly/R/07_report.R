# =============================================================================
# 07_report.R - Grafiken, Beobachtungslisten, Markdown-Bericht
# =============================================================================
FM <- readRDS(file.path(DIR$proc, "final_models.rds"))
TLAB <- c(conflict = "Gewaltkonflikt (>= 25 Tote in 3 Monaten)", fx = "Währungskrise (>= 15 % Abwertung in 3 Monaten)")
MLAB <- c(persistence = "Persistenz (naiv)", rule = "Faustregel (1 Variable)", logit = "Logit (Kernvariablen)",
          enet_struct = "Elastic Net - Struktur", enet_news = "Elastic Net - nur News",
          enet_full = "Elastic Net - Struktur+News", rf_struct = "Random Forest - Struktur",
          rf_full = "Random Forest - Struktur+News", gbm_struct = "Boosting - Struktur",
          gbm_full = "Boosting - Struktur+News", gbm_struct_long = "Boosting - Struktur, Training ab 2011",
          ensemble = "Ensemble (EN+RF+GBM, mit News)",
          timesfm3_zs = "TimesFM 3 (zero-shot)", chronos2_zs = "Chronos-2 (zero-shot)", moirai2_zs = "Moirai-2 (zero-shot)",
          fm_stack = "Foundation-Stack (kalibriert)", enet_hybrid = "Elastic Net - Hybrid (+Foundation)",
          rf_hybrid = "Random Forest - Hybrid (+Foundation)", gbm_hybrid = "Boosting - Hybrid (+Foundation)",
          ensemble_hybrid = "Ensemble - Hybrid (+Foundation)")
FAM <- c(persistence = "Benchmark", rule = "Benchmark", logit = "Statistisch", enet_struct = "Regularisiert",
         enet_news = "Nur News", enet_full = "Regularisiert", rf_struct = "Machine Learning", rf_full = "Machine Learning",
         gbm_struct = "Machine Learning", gbm_full = "Machine Learning", gbm_struct_long = "Machine Learning",
         ensemble = "Ensemble", timesfm3_zs = "Foundation (zero-shot)", chronos2_zs = "Foundation (zero-shot)",
         moirai2_zs = "Foundation (zero-shot)", fm_stack = "Foundation (zero-shot)", enet_hybrid = "Hybrid",
         rf_hybrid = "Hybrid", gbm_hybrid = "Hybrid", ensemble_hybrid = "Hybrid")
FCOL <- c(Benchmark = "#8a8984", Statistisch = PAL[["aqua"]], Regularisiert = PAL[["blue"]],
          `Nur News` = PAL[["orange"]], `Machine Learning` = PAL[["violet"]], Ensemble = PAL[["red"]],
          `Foundation (zero-shot)` = PAL[["yellow"]], Hybrid = PAL[["magenta"]])
cap <- sprintf("Quellen: UCDP GED/Candidate, World Bank GEM/WDI/WGI, Wikipedia Current Events. Out-of-sample %s bis %s, Neutraining alle %d Monate.",
               format(min(preds$month), "%m/%Y"), format(max(preds$month), "%m/%Y"), CFG$refit_every)
res <- res |> mutate(label = MLAB[model], family = FAM[model], tlab = TLAB[target])

# 1) Leistung: Ausbruchs-AUC (Frühwarnung) und Gesamt-AUC
ord <- res |> filter(target == "conflict") |> arrange(auc_onset) |> pull(label)
p1 <- ggplot(res, aes(y = factor(label, levels = ord), colour = family)) +
  geom_segment(aes(x = onset_lo, xend = onset_hi, yend = factor(label, levels = ord)), linewidth = 0.9, alpha = 0.55) +
  geom_point(aes(x = auc_onset), size = 2.8) +
  geom_point(aes(x = auc_hard), shape = 4, size = 2.4, colour = INK$secondary) +
  geom_point(aes(x = auc), shape = 1, size = 2.4, colour = INK$secondary) +
  facet_wrap(~tlab) + scale_colour_manual(values = FCOL) + guides(colour = guide_legend(nrow = 2)) +
  labs(x = "ROC-AUC  (● Ausbrüche, 95 %-KI   × schwierige Fälle   ○ alle Länder-Monate)", y = NULL,
       title = "Wie gut erkennen die Modelle neue Krisen?", caption = cap) + theme_risk()
save_fig(p1, "01_performance.png", 13, 8)

# 2) Mehrwert: News, Foundation-Modelle, ML gegenüber Faustregel
ng <- gains |> mutate(metric = factor(metric, levels = unname(NEWS_METRICS)), tlab = TLAB[target],
                      what = paste0(block, ": ", method))
save_fig(ggplot(ng, aes(delta, what)) +
  geom_vline(xintercept = 0, colour = INK$secondary, linewidth = 0.3) +
  geom_segment(aes(x = lo, xend = hi, yend = what, colour = block), linewidth = 0.9, alpha = 0.6) +
  geom_point(aes(colour = block), size = 2.6) +
  facet_grid(tlab ~ metric, scales = "free_x", labeller = labeller(tlab = label_wrap_gen(22))) +
  scale_colour_manual(values = c(News = PAL[["orange"]], Foundation = PAL[["magenta"]],
                                 `ML vs. Faustregel` = PAL[["red"]], `Foundation vs. Faustregel` = PAL[["yellow"]])) +
  labs(x = "Differenz der AUC (mit minus ohne Baustein), 95 %-KI", y = NULL,
       title = "Was bringt welcher Baustein?", caption = cap) + theme_risk(), "02_value_added.png", 13, 7.5)

# 3) Kalibrierung Ensemble
cal <- preds |> filter(model == "ensemble") |> group_by(target) |> mutate(bin = ntile(p, 10)) |>
  group_by(target, bin) |> summarise(p = mean(p), obs = mean(y), .groups = "drop") |> mutate(tlab = TLAB[target])
save_fig(ggplot(cal, aes(p, obs)) + geom_abline(linetype = 2, colour = INK$secondary) +
  geom_line(colour = PAL[["blue"]], linewidth = 0.7) + geom_point(colour = PAL[["blue"]], size = 2) +
  facet_wrap(~tlab) + coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
  labs(x = "Vorhergesagte Wahrscheinlichkeit", y = "Beobachtete Häufigkeit", title = "Kalibrierung des Ensembles (Dezile)",
       caption = cap) + theme_risk(), "03_calibration.png", 10, 5.5)

# 4) Stabilität über die Zeit
save_fig(ggplot(filter(by_half, model %in% c("ensemble", "gbm_struct", "logit")),
                aes(half, auc_onset, colour = MLAB[model])) +
  geom_line(linewidth = 0.7) + geom_point(size = 2) + facet_wrap(~TLAB[target], ncol = 1) +
  scale_colour_manual(values = unname(PAL[c("red", "violet", "aqua")])) +
  labs(x = NULL, y = "AUC Ausbrüche", title = "Frühwarnqualität je Halbjahr", caption = cap) + theme_risk(),
  "04_auc_over_time.png", 9, 6.5)

# 5) Treiber (Random-Forest-Permutationswichtigkeit, Ensemble-Endmodell)
grp <- function(f) case_when(startsWith(f, "c_") ~ "Konfliktgeschichte", startsWith(f, "m_") ~ "Makro monatlich",
                             startsWith(f, "s_") ~ "Struktur jährlich", TRUE ~ "News")
GCOL <- c(Konfliktgeschichte = PAL[["red"]], `Makro monatlich` = PAL[["blue"]], `Struktur jährlich` = PAL[["aqua"]],
          `News` = PAL[["orange"]])
imp <- imap_dfr(FM, \(x, t) head(x$imp_rf, 15) |> mutate(target = TLAB[t], group = grp(feature)))
save_fig(ggplot(imp, aes(importance, tidytext::reorder_within(feature, importance, target), fill = group)) +
  geom_col(width = 0.65) + tidytext::scale_y_reordered() + facet_wrap(~target, scales = "free") +
  scale_fill_manual(values = GCOL, limits = names(GCOL), drop = FALSE) +
  labs(x = "Permutations-Wichtigkeit (Random Forest)", y = NULL, title = "Wichtigste Frühindikatoren") + theme_risk(),
  "05_drivers.png", 12, 6.5)

# 6) Fallbeispiele: grösste Konfliktausbrüche im Testzeitraum
top_eps <- eps |> filter(target == "conflict", model == "ensemble") |>
  left_join(P$panel |> select(iso3c, month, fut_deaths, country), by = c("iso3c", "start" = "month")) |>
  arrange(desc(fut_deaths)) |> distinct(iso3c, .keep_all = TRUE) |> head(4)
cs <- preds |> filter(target == "conflict", model == "ensemble", iso3c %in% top_eps$iso3c) |>
  left_join(P$panel |> select(iso3c, month, deaths, country), by = c("iso3c", "month"))
cs_marks <- top_eps |> select(iso3c, country, start)
q1 <- ggplot(cs, aes(month, 100 * p)) + geom_line(colour = PAL[["red"]], linewidth = 0.7) +
  geom_vline(data = cs_marks, aes(xintercept = start), linetype = 2, colour = INK$secondary) +
  facet_wrap(~country, nrow = 1) + labs(x = NULL, y = "Risiko (%)", title = "Fallbeispiele: Prognose vor grossen Konfliktausbrüchen",
                                        subtitle = "Gestrichelt: erster Monat, in dem in den Folgemonaten >= 25 Tote eintreten") + theme_risk()
q2 <- ggplot(cs, aes(month, deaths)) + geom_col(fill = INK$secondary, width = 25) + facet_wrap(~country, nrow = 1) +
  scale_y_continuous(trans = "log1p", breaks = c(0, 10, 100, 1000, 10000)) +
  labs(x = NULL, y = "Tote pro Monat (UCDP)", caption = cap) + theme_risk()
save_fig(q1 / q2, "06_case_studies.png", 13, 7)

# 7) Aktuelle Beobachtungslisten
fc_month <- format(add_months(P$last_ucdp, 1), "%m/%Y"); fc_end <- format(add_months(P$last_ucdp, CFG$horizon), "%m/%Y")
wl <- imap_dfr(FM, \(x, t) bind_rows(
  x$watch |> filter(quiet) |> head(12) |> mutate(group = "Frühwarnung: derzeit ruhig"),
  x$watch |> filter(!quiet) |> head(8) |> mutate(group = "Bereits betroffen")) |> mutate(tlab = TLAB[t])) |>
  mutate(key = tidytext::reorder_within(country, risk, tlab))
save_fig(ggplot(wl, aes(100 * risk, key, fill = group)) + geom_col(width = 0.65) +
  geom_text(aes(label = sprintf("%.0f", 100 * risk)), hjust = -0.2, size = 3, colour = INK$secondary) +
  tidytext::scale_y_reordered() + facet_wrap(~tlab, scales = "free") +
  scale_fill_manual(values = c(`Frühwarnung: derzeit ruhig` = PAL[["blue"]], `Bereits betroffen` = PAL[["red"]])) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.12))) +
  labs(x = sprintf("Wahrscheinlichkeit %s - %s (%%)", fc_month, fc_end), y = NULL,
       title = sprintf("Beobachtungsliste für %s bis %s", fc_month, fc_end),
       caption = sprintf("Datenstand: Konflikt %s, Makro %s, News %s.", format(P$last_ucdp, "%m/%Y"),
                         format(P$last_fx_month, "%m/%Y"), format(P$news_last, "%d.%m.%Y"))) +
  theme_risk(), "07_watchlist.png", 13, 7.5)

# ---------- Markdown ----------
md_table <- function(df, digits = 3) {
  fmt <- function(x) if (all(is.na(x) | x == round(x))) ifelse(is.na(x), "-", format(x)) else
    ifelse(is.na(x), "-", formatC(x, digits = digits, format = "f"))
  df <- mutate(df, across(where(is.numeric), fmt))
  c(paste0("| ", paste(names(df), collapse = " | "), " |"), paste0("|", strrep("---|", ncol(df))),
    apply(df, 1, \(r) paste0("| ", paste(r, collapse = " | "), " |")))
}
tab <- function(t) res |> filter(target == t) |> transmute(Rang = rank, Methode = label,
  `AUC Ausbrüche` = auc_onset, `KI` = sprintf("%.2f-%.2f", onset_lo, onset_hi), `AUC schwierig` = auc_hard,
  `PR-AUC Ausbr.` = pr_onset, `Ausbrüche auf Liste` = sprintf("%d/%d", episodes_warned, onset_episodes),
  Lift = lift, `Treffer Liste` = list_precision, `AUC alle` = auc, BSS = bss, `Kal.-Steigung` = cal_slope)
wtab <- function(t, quiet_only) FM[[t]]$watch |> filter(quiet == quiet_only) |> head(15) |>
  transmute(Land = country, Region = region, `Risiko Ensemble` = risk, `Elastic Net` = p_enet, `Random Forest` = p_rf,
            Boosting = p_gbm, across(any_of(c(`Hybrid-Ensemble` = "risk_hybrid", `Chronos-2` = "p_chronos2",
                                              `TimesFM 3` = "p_timesfm3", `Moirai-2` = "p_moirai2"))))
r <- res |> filter(model == "ensemble")

report <- c("# Monatliches Frühwarnsystem - automatischer Evaluationsbericht", "",
  sprintf("_Erzeugt am %s. Alle Kennzahlen sind echte Out-of-sample-Werte: Testmonate %s bis %s, Neutraining alle %d Monate._",
          format(Sys.Date(), "%d.%m.%Y"), format(min(preds$month), "%m/%Y"), format(max(preds$month), "%m/%Y"), CFG$refit_every), "",
  "## Datengrundlage", "",
  sprintf("* %d Länder (>= 1 Mio. Einwohner), Monatsdaten %s bis %s", n_distinct(P$panel$iso3c),
          format(min(P$panel$month), "%m/%Y"), format(P$last_ucdp, "%m/%Y")),
  sprintf("* Features: %d strukturierte (Konflikt inkl. räumlich, Makro monatlich, Struktur) + %d News-Features + %d Foundation-Prognosen",
          length(STRUCT), length(NEWS), length(c(P$FM_C, P$FM_X))),
  sprintf("* Testdaten Konflikt: %d Länder-Monate, davon %d Ausbruchs-Monate in %d Episoden", r$n[r$target == "conflict"],
          r$onset_events[r$target == "conflict"], r$onset_episodes[r$target == "conflict"]),
  sprintf("* Testdaten Währung: %d Länder-Monate, davon %d Ausbruchs-Monate in %d Episoden", r$n[r$target == "fx"],
          r$onset_events[r$target == "fx"], r$onset_episodes[r$target == "fx"]), "",
  "## Gewaltkonflikt", "", md_table(tab("conflict")), "",
  "## Währungskrise", "", md_table(tab("fx")), "",
  "_Ausbrüche = Länder, die in den 12 Monaten davor unter der Schwelle lagen. Schwierige Fälle = ruhige Länder mit Vorzeichen (Konflikt: mindestens 1 Toter in 12 Monaten; Währung: mehr als 5 % Abwertung in 12 Monaten) - hier entscheidet sich, ob ein Modell mehr kann als eine Faustregel. 'Ausbrüche auf Liste' = Episoden, bei denen das Land vorher mindestens einmal unter den Top 20 der ruhigen Länder stand. Lift = wie viel Mal mehr Ausbrüche die Liste enthält als eine Zufallsauswahl gleicher Grösse. 'Treffer Liste' = Anteil der Listenplätze mit tatsächlichem Ausbruch._", "",
  "![Leistung](figures/01_performance.png)", "",
  "## Was bringt welcher Baustein?", "",
  "News = Wikipedia-Nachrichtenticker; Foundation = Zero-shot-Prognosen von TimesFM 3, Chronos-2 und Moirai-2 als Zusatz-Features; Faustregel = Logit mit einer einzigen Variable.", "",
  md_table(gains |> transmute(Ziel = TLAB[target], Baustein = block, Methode = method, Metrik = metric, Delta = delta,
                              `KI unten` = lo, `KI oben` = hi, `P(Delta>0)` = p_gt0)), "",
  "![Mehrwert](figures/02_value_added.png)", "",
  "## Diagnostik", "", "![Kalibrierung](figures/03_calibration.png)", "", "![Zeit](figures/04_auc_over_time.png)", "",
  "![Treiber](figures/05_drivers.png)", "", "![Fälle](figures/06_case_studies.png)", "",
  sprintf("## Beobachtungsliste %s bis %s", fc_month, fc_end), "", "![Watchlist](figures/07_watchlist.png)", "",
  "### Gewaltkonflikt - Frühwarnung (derzeit ruhige Länder)", "", md_table(wtab("conflict", TRUE)), "",
  "### Währungskrise - Frühwarnung (derzeit ruhige Länder)", "", md_table(wtab("fx", TRUE)))
writeLines(report, file.path(DIR$out, "report.md"))
log_msg("Bericht geschrieben: %s", file.path(DIR$out, "report.md"))
