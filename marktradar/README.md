# Marktradar Krankenversicherung

**Wie stark verändert sich der Marktanteil eines Krankenversicherers im nächsten Jahr,
und wie hängt das von seiner Prämienanpassung im Vergleich zur Konkurrenz ab?**

Marktradar beantwortet diese Frage mit einem ML-Modell, das ausschliesslich auf
**öffentlichen Daten des BAG** trainiert ist (Aufsichtsdaten OKP, alle Versicherer,
2006–2024). Keine Kunden- oder Zahlungsdaten nötig.

## Wofür im Vertrieb?

| Frage | Endpoint / Befehl |
|---|---|
| Wer gewinnt, wer verliert im Markt? | `GET /markt` |
| Was bedeutet es für unseren Bestand, wenn wir 2 %-Punkte über dem Markt aufschlagen? | `POST /prognose` |
| Wie preissensitiv ist der Bestand eines Versicherers? (Elastizitätskurve) | `POST /elastizitaet` |
| Wo stehen Konkurrenten bei Prämie, Reserven, Kosten? | `GET /versicherer` |

Beispiel (CSS, Basisjahr 2024): Prämie +1 %-Punkt über Markt → Marktanteil
**−0.75 %** (80 %-Intervall −2.2 % bis +0.3 %), rund **11'500 Versicherte** weniger.

## Ergebnisse (Backtest 2014–2023, ausserhalb der Trainingszeit)

| Metrik | Modell | Baseline „Anteil bleibt gleich“ | Baseline „wie Vorjahr“ |
|---|---|---|---|
| MAE Marktanteilswachstum (log) | **0.047** | 0.067 | 0.090 |
| Rangkorrelation (Gewinner/Verlierer) | **0.76** | – | – |
| Abdeckung 80 %-Intervall | 0.75 (roh 0.62) | – | – |

→ **30 % genauer** als die naive Prognose. Details und Grenzen: [MODEL_CARD.md](MODEL_CARD.md).

## Schnellstart

Voraussetzung: [uv](https://docs.astral.sh/uv/).

```bash
cd marktradar
uv sync
make pipeline        # download -> build -> train (ca. 1-2 Min.)
uv run marktradar predict 8 --kurve
make serve           # http://localhost:8000/docs
```

**Windows (PowerShell)**: `make` gibt es dort nicht, stattdessen `tasks.ps1`:

```powershell
cd marktradar
powershell -ExecutionPolicy Bypass -File .\tasks.ps1 pipeline
powershell -ExecutionPolicy Bypass -File .\tasks.ps1 serve
```

Oder alles im Container (trainiert beim Build):

```bash
docker build -t marktradar .
docker run --rm -p 8000:8000 marktradar
```

API-Beispiel:

```bash
curl -X POST localhost:8000/prognose -H 'Content-Type: application/json' \
     -d '{"bag_nr": 8, "praemienanpassung_rel_pp": 1}'
```

BAG-Nummern der grössten Versicherer: 8 CSS, 1562 Helsana, 1384 SWICA, 1542 Assura,
290 Concordia, 1509 Sanitas, 376 KPT, 1555 Visana (`GET /versicherer` für alle).

## Architektur

```
 BAG Excel ──download──> data/raw ──build──> data/processed/panel.parquet
 (sha256 geprüft)               (parsen + validieren)        │
                                                             ▼
                          features.py: marktrelative Kennzahlen, Ziel = Δ log-Marktanteil
                                                             │
                                                             ▼
          model.py: Rolling-Backtest ──> Conformal-Kalibrierung ──> finales Modell
                                                             │
                                                             ▼
          registry.py: models/<version>/ + Quality Gate ──> production.json
                                                             │
                              ┌──────────────────────────────┴───────────┐
                              ▼                                          ▼
                   service.py (Fachlogik)  <───────────────  cli.py / api.py (FastAPI)
```

| Datei | Verantwortung |
|---|---|
| `config/config.yaml` | Alle Einstellungen (Datenquelle, Filter, Hyperparameter, Gate) |
| `src/marktradar/data.py` | Download mit Prüfsumme, robuster Parser (über BAG-Spaltencodes), Validierung |
| `src/marktradar/features.py` | Feature Engineering, Zeitlogik gegen Data Leakage |
| `src/marktradar/model.py` | Gradient Boosting + Quantile + Conformal, zeitlicher Backtest |
| `src/marktradar/registry.py` | Versionierte Modelle, Quality Gate, Rollback |
| `src/marktradar/service.py` | Prognosen/Szenarien (von API und CLI genutzt) |
| `src/marktradar/api.py`, `cli.py` | Schnittstellen |
| `tests/` | 35 Tests auf synthetischen Daten mit bekanntem Effekt |

## Was du hier an ML- und Deployment-Praxis lernen kannst

1. **Zeitreihen-Validierung**: Rolling-Origin-Backtest statt zufälligem Split
   (`model.backtest`). Ein Test prüft, dass nie mit Testjahr-Daten trainiert wird.
2. **Data Leakage vermeiden**: Jede Feature-Spalte ist dokumentiert mit „wann ist
   das bekannt?“ (`features.py`).
3. **Ehrliche Baselines**: Ein Modell ist nur so gut wie sein Abstand zur einfachsten
   Alternative.
4. **Domänenwissen als Constraint**: Monotone Constraints (höhere Prämie → nie mehr
   Wachstum) machen das Modell robust und erklärbar.
5. **Unsicherheit quantifizieren**: Quantilregression + *Conformal Prediction* (CQR).
   Die rohen Intervalle waren zu optimistisch (62 % statt 80 %), nach Kalibrierung 75 %.
6. **Robuste Datenpipelines**: Parser orientiert sich an stabilen Codes statt an
   Spaltenpositionen; Validierung bricht bei unplausiblen Daten ab.
7. **MLOps**: Modell-Registry, Quality Gate vor dem Produktivsetzen, Metadaten
   (Daten-Hash, Git-Commit, Metriken) zu jeder Version, Rollback per `marktradar promote`.
8. **Deployment**: Multi-Stage-Docker (Training im Build → reproduzierbares Image),
   non-root, Healthcheck, Firmen-Registry/-Proxy unterstützt.
9. **CI/CD**: `.github/workflows/marktradar.yml`: Lint, Typen, Tests bei jedem Push;
   monatliches Retraining auf echten Daten + Container-Smoke-Test.

## Wartung

**Jährliches Update** (das BAG publiziert die neuen Aufsichtsdaten jeweils im Herbst):

1. Neue URL von der [BAG-Seite](https://www.bag.admin.ch/de/aufsichtsdaten-krankenversicherer)
   in `config/config.yaml` eintragen, `sha256` leeren.
2. `make pipeline`: Neue Version wird nur produktiv, wenn sie das Quality Gate besteht.
3. Bei Problemen: `uv run marktradar promote <alte-version>` (Rollback).

Qualität sichern: `make lint test`.

## Ideen zum Weiterbauen

- **Regionale Sicht**: BAG-Prämiendaten pro Prämienregion/Kanton (opendata.swiss) +
  BFS-Bevölkerungsdaten → Wechselpotenzial je Region für die Vertriebssteuerung.
- **Echte Prämienankündigungen** (September, priminfo.admin.ch) statt der realisierten
  Durchschnittsprämie als Hebel-Feature.
- **Erklärbarkeit pro Prognose** (SHAP) in der API ausgeben.
- **Monitoring**: Prognosen speichern und nach Publikation der Ist-Daten automatisch auswerten.
- **Dashboard** (Streamlit) auf der API für Kolleginnen und Kollegen ohne Technikhintergrund.
