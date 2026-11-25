# FinanzDashboard (Power BI Project)

Power-BI-Projekt (`.pbip`, PBIR + TMDL) mit S&P-500-Daten im Streamlit-Look.

## Datenquellen (werden beim Aktualisieren per HTTP geladen)

- S&P 500 Monatsdaten (Index, Zins, Shiller-KGV):
  `datasets/s-and-p-500`
- Unternehmenskennzahlen: `datasets/s-and-p-500-companies-financials`
- GICS-Sektoren: `datasets/s-and-p-500-companies`

## Öffnen

1. Power BI Desktop (aktuelle Version) öffnen.
2. Falls nötig unter *Optionen > Vorschaufeatures* „Power BI-Projekt (.pbip)
   speichern" und „PBIR-Format" aktivieren.
3. `FinanzDashboard.pbip` öffnen und **Aktualisieren** klicken (Datenquelle
   „Web" mit anonymem Zugriff bestätigen).

## Seiten

- **S&P 500 Markt**: KPI-Karten, Indexverlauf, Zins vs. Shiller-KGV,
  Jahresrenditen
- **Unternehmen**: Sektor-Slicer, KPI-Karten, Marktkapitalisierung und
  Median-KGV nach Sektor, Tabelle der grössten Unternehmen
- **Python-Visuals**: dieselben Charts als matplotlib-Skripte im
  Streamlit-Stil. Voraussetzung: lokales Python mit `pandas` und
  `matplotlib`, in Power BI unter *Optionen > Python-Skripterstellung*
  hinterlegt. Beim Öffnen Python-Visuals aktivieren.
- **R-Visuals** (ggplot2), Charts ohne natives Power-BI-Pendant:
  Violin-/Boxplot der Monatsrenditen pro Jahrzehnt, CAPE vs.
  10-Jahres-Rendite mit LOESS-Kurve und 2D-Dichte, Kalender-Heatmap,
  KGV-Dichten pro Sektor als Small Multiples. Voraussetzung: R >= 4.1
  mit `dplyr`, `ggplot2`, `tidyr`, `scales`, in Power BI unter
  *Optionen > R-Skripterstellung* hinterlegt.

Die Streamlit-App dazu liegt in `../finanz_streamlit/`.
