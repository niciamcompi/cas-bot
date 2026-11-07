# Monatliches Frühwarnsystem (R)

Ein Frühwarnsystem auf **Monatsbasis** für 156 Länder, gebaut nur aus öffentlichen Daten. Es sagt für die
**nächsten 3 Monate** zwei Arten von Krisen voraus:

| Ziel | Definition | Quelle |
|---|---|---|
| **Gewaltkonflikt** | ≥ 25 Todesopfer organisierter Gewalt in den Monaten t+1 bis t+3 | UCDP GED + GED Candidate (monatlich) |
| **Währungskrise** | Abwertung der Landeswährung ggü. USD um ≥ 15 % von t bis t+3 | World Bank Global Economic Monitor |

Bewertet wird vor allem die Erkennung von **Ausbrüchen**: Krisen in Ländern, die in den 12 Monaten davor
ruhig waren. Laufende Krisen fortzuschreiben ist trivial, gefragt ist die echte Frühwarnung.

> Automatischer Bericht mit allen Tabellen und Grafiken: [`output/report.md`](output/report.md)
> Aktuelle Beobachtungslisten: `output/watchlist_conflict.csv`, `output/watchlist_fx.csv`

## Daten (alle öffentlich, ohne API-Schlüssel)

| Quelle | Inhalt | Aktualität |
|---|---|---|
| **UCDP GED 26.1 + Candidate** (ucdp.uu.se) | Jedes Gewaltereignis weltweit mit Datum, Ort und Toten, getrennt nach staatlicher, nichtstaatlicher und einseitiger Gewalt | Monatlich, ca. 1 Monat Verzug |
| **World Bank GEM** (Quelle 15) | Monatlich: Wechselkurs, Konsumentenpreise, Währungsreserven, Industrieproduktion, Aktienindex | 1–2 Monate Verzug |
| **World Bank WDI/WGI** | Jährlich (Vorjahreswerte): BIP pro Kopf, Bevölkerung, Kindersterblichkeit, Jugendanteil, politische Stabilität, Regierungseffektivität, Mitsprache | Jährlich |
| **Wikipedia „Portal:Current events“** | **Schnelle Textdaten**: täglicher Nachrichtenticker mit Quellen (Reuters, BBC, AP …), 55'000+ Meldungen seit 2017 | **Tagesaktuell** |
| GDELT DOC 2.0 (optional) | Tonalität und Themenvolumen der weltweiten Online-News | Tagesaktuell, stark gedrosselt |

### Text Mining der Nachrichten (`R/03_fetch_news.R`)

Jede Meldung des Tickers wird automatisch zerlegt:
1. **Rubrik**: Konflikt/Anschläge, Politik/Wahlen, Kriminalität, Wirtschaft, Katastrophen, Diplomatie, Gesundheit
2. **Länder**: per Wörterbuch aus Ländernamen, Adjektiven und Hauptstädten (inkl. übergeordneter Themenzeilen wie „Sudanese civil war“)
3. **Tonalität**: Anteil negativer Wörter (Bing-Lexikon)

Daraus entstehen pro Land und Monat 18 Features, z. B. Zahl der Konfliktmeldungen, Konfliktanteil an der
Berichterstattung, Abweichung vom eigenen 12-Monats-Mittel (z-Wert), Trend über 3 Monate und Negativität.
Pro Monat genügt **eine API-Anfrage**, und alte Monate werden gecacht.

> **Warum Wikipedia statt GDELT?** GDELT erlaubt höchstens eine Anfrage alle 5 Sekunden und blockiert geteilte
> Cloud-IPs oft komplett. Hier kam in 10 Minuten keine einzige Anfrage durch. Der GDELT-Code ist als optionale
> Zusatzquelle enthalten (`USE_GDELT=1`). Lokal funktioniert er meist, der Erstabruf dauert aber 60–90 Minuten.

## Methoden (`R/05_models.R`)

| Methode | Beschreibung |
|---|---|
| Persistenz | Naiver Benchmark: Basisrate je nach aktueller Lage |
| Logit | Logistische Regression mit 10 Kernvariablen |
| Elastic Net | Regularisierte Logit (glmnet), je **nur Struktur**, **nur News** und **Struktur+News** |
| Random Forest | ranger, Struktur bzw. Struktur+News |
| Gradient Boosting | gbm, Struktur bzw. Struktur+News, zusätzlich **Struktur mit langer Historie ab 2011** |
| Ensemble | Mittel aus Elastic Net, Random Forest und Boosting (je mit News) |

**Evaluation (`R/06_evaluation.R`):** echte Out-of-sample-Prognosen für die Monate 01/2021–06/2026. Alle 6 Monate
wird neu trainiert, nur mit Daten, deren Ergebnis zu diesem Zeitpunkt schon bekannt war. Die Kennzahlen:
- AUC und PR-AUC, gemessen auf ruhigen Ländern (also für Ausbrüche)
- Kalibrierung (Brier, Brier Skill Score, Kalibrierungs-Steigung)
- **Beobachtungsliste**: jeden Monat die Top 20 der ruhigen Länder. Wie viele Ausbrüche standen vorher darauf?
- Länder-Cluster-Bootstrap für Konfidenzintervalle und für den Mehrwert der News

## Ergebnisse

### Gewaltkonflikt: 25 Ausbrüche im Testzeitraum

| Methode | AUC Ausbrüche (95 %-KI) | Ausbrüche auf Liste | AUC alle | Brier Skill |
|---|---|---|---|---|
| **Ensemble (mit News)** | **0.85** (0.76–0.91) | **20/25** | 0.987 | 0.81 |
| Random Forest – Struktur+News | 0.86 (0.77–0.92) | 21/25 | 0.987 | 0.81 |
| Random Forest – Struktur | 0.84 (0.76–0.91) | 18/25 | 0.986 | 0.81 |
| Logit (Kernvariablen) | 0.82 (0.72–0.89) | 19/25 | 0.985 | 0.80 |
| Elastic Net – nur News | 0.71 (0.60–0.81) | 12/25 | 0.860 | 0.38 |
| Persistenz (naiv) | ≈ Zufall | 9/25 | 0.919 | 0.73 |

### Währungskrise: 36 Ausbrüche im Testzeitraum

| Methode | AUC Ausbrüche (95 %-KI) | Ausbrüche auf Liste | AUC alle | Brier Skill |
|---|---|---|---|---|
| **Boosting – Struktur, Training ab 2011** | **0.87** (0.83–0.90) | **25/36** | 0.915 | 0.22 |
| Ensemble (mit News) | 0.81 (0.76–0.86) | 20/36 | 0.893 | 0.16 |
| Random Forest – Struktur+News | 0.77 (0.70–0.84) | 19/36 | 0.875 | 0.12 |
| Logit (Kernvariablen) | 0.69 (0.57–0.81) | 13/36 | 0.837 | 0.05 |
| Elastic Net – nur News | 0.34 (schlechter als Zufall) | 5/36 | 0.425 | 0.00 |

![Leistung](output/figures/01_performance.png)

### Bewertung

1. **Im Vergleich zum Jahresmodell ist die Frühwarnung klar besser.** Neue Konflikte werden mit einer AUC von
   0,85 erkannt, beim Jahresmodell waren es 0,70–0,74. Monatliche Daten zur Gewalt- und Nachrichtenlage reagieren
   viel schneller als Jahresstatistiken.
2. **Die Beobachtungsliste lohnt sich.** Die Top 20 von rund 112 ruhigen Ländern (18 %) enthielten **80 % aller
   späteren Konfliktausbrüche**. Eine Zufallsauswahl hätte etwa 18 % getroffen, das ist also rund **4,5-mal besser als
   Zufall**. Aber: Nur etwa 3 % der Listenplätze führen tatsächlich zu einem Ausbruch. Die Liste ist ein Filter für
   genauere Analysen, kein Alarm.
3. **Die Wahrscheinlichkeiten bleiben niedrig.** Selbst das gefährdetste ruhige Land liegt meist unter 10 %.
   Ausbrüche sind seltene Ereignisse (0,85 % der ruhigen Länder-Monate). Ehrlicherweise heisst das: Ein Modell kann
   sie eingrenzen, aber nicht sicher vorhersagen.
4. **Die Fallbeispiele zeigen die Grenzen** (`output/figures/06_case_studies.png`). Plötzliche Gewalt wie in
   Armenien (2022) oder Tansania (Wahlen 2025) sieht das Modell vorher kaum. Nach dem ersten Gewaltmonat springt das
   Risiko aber sofort hoch, ein Monat Verzug statt eines ganzen Jahres.
5. **Für Währungskrisen gewinnt das einfachste ML-Modell mit der längsten Historie.** Boosting mit Daten ab 2011
   (0,87) schlägt alle Modelle ab 2018. Währungskrisen sind selten, mehr Beispiele zählen mehr als mehr Variablen.
   Wichtigste Signale: schwache Institutionen (politische Stabilität, Regierungseffektivität),
   Wechselkurs-Volatilität und die Abwertung der letzten 12 Monate. Bei Konflikten dominiert die jüngste
   Gewaltgeschichte (Tote und Ereignisse der letzten 1–12 Monate), siehe `output/figures/05_drivers.png`.
   Die News-Features erscheinen in keiner der beiden Top-15-Listen.
6. **Die Methoden liegen nah beieinander.** Die Konfidenzintervalle überlappen stark. Empfehlung: **Ensemble für
   Konflikte, Boosting mit langer Historie für Währungskrisen.**

### Was bringen die schnellen Textdaten?

![News](output/figures/02_news_value.png)

* **Allein haben sie Signal für Konflikte** (AUC 0,71 bei Ausbrüchen), für Währungskrisen aber keines. Wikipedia
  berichtet über Wechselkurse nur selten.
* **Zusätzlich zu den Strukturdaten** verbessern sie den Random Forest bei Konfliktausbrüchen leicht, aber
  statistisch gesichert: AUC +0,018 (KI 0,001–0,032), 21 statt 18 erkannte Ausbrüche. Beim Elastic Net und beim
  Boosting gibt es keinen Effekt.
* Bei Währungskrisen hilft der Text nur dem schwachen Elastic Net (+0,09), den besten Modellen nicht.
* **Fazit:** Der Nachrichtenticker liefert einen kleinen, echten Mehrwert für die Konflikt-Frühwarnung, der
  grösste Gewinn kommt aber von den monatlichen Gewaltdaten selbst. Ein dichterer Nachrichtenstrom (GDELT lokal
  aktivieren) könnte mehr bringen.

### Aktuelle Beobachtungsliste (Oktober–Dezember 2026)

![Watchlist](output/figures/07_watchlist.png)

## Grenzen

* **Datenverzug:** UCDP-Candidate-Daten erscheinen etwa einen Monat später, die Makrodaten 1–2 Monate.
  Die Evaluation geht davon aus, dass die Daten am Monatsende vorliegen. Im Echtbetrieb ist der Vorsprung kleiner.
* **Vorläufige Daten:** Die UCDP-Candidate-Daten werden später noch korrigiert.
* Länder **ohne aktuelle Wechselkursdaten** (z. B. Sudan, Iran, Syrien) fehlen in der Währungs-Watchlist.
* Die **Ländererkennung im Text** arbeitet mit einem Wörterbuch. Mehrdeutige Namen (Georgia, Jordan, Guinea) sind
  abgefangen, aber nicht perfekt.
* Wikipedia ist **englischsprachig und westlich geprägt**. Kleine Länder kommen selten vor.

## Ausführen

Voraussetzungen: R ≥ 4.3 und Internet (api.worldbank.org, ucdp.uu.se, en.wikipedia.org).

```r
install.packages(c("dplyr", "tidyr", "purrr", "stringr", "readr", "jsonlite", "ggplot2", "patchwork",
                   "countrycode", "glmnet", "ranger", "gbm", "pROC", "tidytext", "zoo"))
```

```bash
Rscript run_all.R
```

* Der erste Lauf dauert ca. 25 Minuten (10 Min. Wikipedia, 10 Min. Modelle), Folgeläufe ca. 3 Minuten.
* `RISK_REFRESH=1` lädt UCDP- und Weltbank-Daten neu und trainiert alle Modelle neu. **Das ist der Befehl für das monatliche Update.**
* `USE_GDELT=1` aktiviert GDELT als zusätzliche Nachrichtenquelle.

Automatisch und kostenlos per GitHub Actions: `.github/workflows/update-early-warning.yml` (monatlich am 22.,
nach dem Erscheinen der neuen UCDP-Candidate-Daten).

### Struktur

```
run_all.R                  Pipeline
R/00_config.R              Parameter (Horizont, Schwellen, Testzeitraum), Hilfsfunktionen
R/01_fetch_worldbank.R     GEM-Monatsdaten + jährliche WDI/WGI-Struktur
R/02_fetch_ucdp.R          UCDP GED + Candidate -> Tote pro Land und Monat
R/03_fetch_news.R          Wikipedia Current Events -> Text Mining
R/03b_fetch_gdelt.R        GDELT (optional)
R/04_build_panel.R         Länder-Monats-Panel, Zielvariablen, Features
R/05_models.R              11 Methoden, Rolling-Origin-Evaluation, Beobachtungslisten
R/06_evaluation.R          Kennzahlen, Bootstrap, Mehrwert der News
R/07_report.R              Grafiken und output/report.md
```
