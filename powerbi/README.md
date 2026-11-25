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

Die Streamlit-App dazu liegt in `../finanz_streamlit/`.
