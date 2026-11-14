# Model Card: Marktradar

## Zweck
Prognose der Veränderung des Marktanteils (Versichertenbestand) von Schweizer
OKP-Versicherern vom Basisjahr *t* ins Folgejahr *t+1*, inklusive Szenario für die
Prämienanpassung relativ zum Markt. Zielgruppe: Vertriebs- und Marktanalyse.
**Nicht** gedacht für Tarifierung, Einzelpersonen-Entscheide oder als alleinige
Entscheidungsgrundlage.

## Daten
- Quelle: BAG, Statistik der obligatorischen Krankenversicherung, T 5.01
  „Aufsichtsdaten OKP“, Jahre 2006–2024 (1163 Versicherer-Jahre, 90 Versicherer).
- Öffentlich, aggregiert auf Versicherer-Ebene, keine Personendaten.
- Ausgeschlossen: Versicherer < 1000 Versicherte; Übergänge mit |Δ log-Anteil| > 0.5
  (Fusionen/Bestandesübertragungen, kein Wechselverhalten).

## Ziel und Features
- Ziel: Δ log-Marktanteil t → t+1.
- Features: Prämienanpassung t→t+1 relativ zum Markt (Szenario-Hebel), relatives
  Prämienniveau, letzte Prämienanpassung, Vorjahreswachstum, Reserven, Verwaltungs-
  kosten, Risikoausgleich, Gesamtergebnis (jeweils relativ zum Markt), Marktanteil.

## Modell
`HistGradientBoostingRegressor` (scikit-learn), Median-Loss, Gewichtung √Bestand,
monotone Constraints (Prämie ↑ ⇒ Wachstum nicht ↑). Intervall: Quantilmodelle 10 %/90 %,
nachkalibriert mit Conformalized Quantile Regression auf Out-of-Time-Fehlern.

## Evaluation (Rolling-Origin, Basisjahre 2014–2023)
| Basisjahr | MAE Modell | MAE konstant | Rangkorrelation |
|---|---|---|---|
| 2014 | 0.039 | 0.059 | 0.81 |
| 2015 | 0.033 | 0.057 | 0.78 |
| 2016 | 0.063 | 0.073 | 0.72 |
| 2017 | 0.048 | 0.065 | 0.80 |
| 2018 | 0.023 | 0.046 | 0.80 |
| 2019 | 0.029 | 0.047 | 0.86 |
| 2020 | 0.031 | 0.048 | 0.74 |
| 2021 | 0.050 | 0.066 | 0.70 |
| 2022 | 0.083 | 0.115 | 0.77 |
| 2023 | 0.072 | 0.093 | 0.62 |

Mittel: MAE 0.047 vs. 0.067 (−30 %), Rangkorrelation 0.76, Intervallabdeckung 75 %
(Ziel 80 %).

## Bekannte Grenzen
1. **Hebel-Feature ist ein Proxy.** Verwendet wird die Veränderung der *realisierten*
   Durchschnittsprämie je Person, nicht die im September angekündigte Tarifänderung.
   Diese wird auch durch die Bestandesmischung beeinflusst (gewinnt ein Versicherer
   viele junge Versicherte, sinkt seine Durchschnittsprämie). Die Preiselastizität
   wird dadurch vermutlich **überschätzt**. Szenarien als Richtgrösse lesen.
2. **Strukturbruch 2022/2023**: Nach den starken Prämienerhöhungen 2023/2024 wechselten
   deutlich mehr Personen; Fehler und Intervall-Unterdeckung sind in diesen Jahren höher.
3. **Datenverzug**: Aufsichtsdaten erscheinen mit ca. 1 Jahr Verzögerung. Das Basisjahr
   ist das letzte publizierte Jahr (aktuell 2024 → Prognose 2025).
4. **Kleine Stichprobe**: ca. 40–60 Versicherer pro Jahr. Für kleine Kassen sind die
   Intervalle breit.
5. Gesamtmarktgrösse wird in `bestand_prognose` als konstant angenommen.
6. Keine kausale Aussage: Das Modell lernt Zusammenhänge aus Beobachtungsdaten.

## Verantwortung
Modellartefakte (`models/<version>/metadata.json`) enthalten Daten-Hash, Git-Commit,
Konfiguration und Backtest. Neue Versionen werden nur nach bestandenem Quality Gate
produktiv.
