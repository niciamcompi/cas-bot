"""Feature Engineering.

Grundidee: Kundinnen und Kunden wechseln wegen der Prämie *im Vergleich zur
Konkurrenz*, nicht wegen der absoluten Prämie. Darum wird fast alles relativ zum
(bestandesgewichteten) Marktdurchschnitt des jeweiligen Jahres ausgedrückt. Das
macht die Features über die Jahre vergleichbar, obwohl die Prämien jedes Jahr steigen.

Zeitlogik (wichtig gegen Data Leakage): Eine Zeile beschreibt Versicherer *v* im
Basisjahr *t*. Alle Features stammen aus Jahr *t* oder früher, mit einer Ausnahme:
``praemien_aenderung_rel`` (Prämienanpassung t -> t+1 relativ zum Markt). Diese ist
im echten Leben im September bekannt (BAG-Genehmigung), also *vor* dem Wechseltermin
30. November. Sie ist der Hebel für Szenario-Rechnungen ("Was passiert, wenn wir 2
Prozentpunkte stärker aufschlagen als der Markt?").

Ziel: Veränderung des log-Marktanteils von t nach t+1.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

TARGET = "ziel_anteilswachstum"
LEVER = "praemien_aenderung_rel"

FEATURES: list[str] = [
    LEVER,
    "rel_praemie",  # Prämienniveau vs. Markt (log-Verhältnis)
    "delta_rel_praemie",  # letzte Prämienanpassung vs. Markt (t-1 -> t)
    "anteilswachstum_vorjahr",  # Momentum
    "rel_reserven",  # Reserven je Person vs. Markt (Spielraum für tiefe Prämien)
    "rel_verwaltung",  # Verwaltungskosten je Person vs. Markt
    "risikoausgleich_rel",  # + = Bestand mit hohem Risiko, - = junger/gesunder Bestand
    "ergebnis_rel",  # Gesamtergebnis je Person / Marktprämie
    "log_marktanteil",  # Grösse
]

# Fachwissen als Modell-Constraint: Eine höhere relative Prämie darf die
# Wachstumsprognose nie *erhöhen*. Das macht das Modell robuster und erklärbarer.
MONOTONIC_CONSTRAINTS: dict[str, int] = {LEVER: -1, "rel_praemie": -1}


def _weighted_mean(values: pd.Series, weights: pd.Series) -> float:
    return float(np.average(values, weights=weights))


def market_context(panel: pd.DataFrame) -> pd.DataFrame:
    """Bestandesgewichtete Marktkennzahlen je Jahr (über *alle* Versicherer)."""
    rows = []
    for year, g in panel.groupby("jahr"):
        w = g["versicherte"]
        rows.append(
            {
                "jahr": year,
                "markt_versicherte": float(w.sum()),
                "markt_praemie_pp": _weighted_mean(g["praemie_pp"], w),
                "markt_reserven_pp": _weighted_mean(g["reserven_pp"].fillna(0), w),
                "markt_verwaltung_pp": _weighted_mean(g["verwaltung_pp"].fillna(0), w),
            }
        )
    return pd.DataFrame(rows)


def build_features(panel: pd.DataFrame) -> pd.DataFrame:
    """Panel -> Feature-Tabelle mit einer Zeile je (bag_nr, jahr).

    ``TARGET`` und ``LEVER`` sind NaN, wenn es kein Folgejahr gibt (z.B. letztes
    Datenjahr oder Versicherer ist aus dem Markt ausgetreten).
    """
    df = panel.merge(market_context(panel), on="jahr", how="left")
    df = df.sort_values(["bag_nr", "jahr"]).reset_index(drop=True)

    df["rel_praemie"] = np.log(df["praemie_pp"] / df["markt_praemie_pp"])
    df["rel_reserven"] = np.log(
        df["reserven_pp"].clip(lower=1) / df["markt_reserven_pp"].clip(lower=1)
    )
    df["rel_verwaltung"] = np.log(
        df["verwaltung_pp"].clip(lower=1) / df["markt_verwaltung_pp"].clip(lower=1)
    )
    df["risikoausgleich_rel"] = df["risikoausgleich_pp"] / df["markt_praemie_pp"]
    df["ergebnis_rel"] = (df["ergebnis_pp"] / df["markt_praemie_pp"]).clip(-1, 1)
    df["log_marktanteil"] = np.log(df["versicherte"] / df["markt_versicherte"])

    by = df.groupby("bag_nr")
    prev_year = by["jahr"].shift(1)
    next_year = by["jahr"].shift(-1)
    has_prev = prev_year == df["jahr"] - 1
    has_next = next_year == df["jahr"] + 1

    share_growth = df["log_marktanteil"] - by["log_marktanteil"].shift(1)
    df["anteilswachstum_vorjahr"] = share_growth.where(has_prev)
    df["delta_rel_praemie"] = (df["rel_praemie"] - by["rel_praemie"].shift(1)).where(has_prev)
    df[LEVER] = (by["rel_praemie"].shift(-1) - df["rel_praemie"]).where(has_next)
    df[TARGET] = (by["log_marktanteil"].shift(-1) - df["log_marktanteil"]).where(has_next)
    df["prognosejahr"] = df["jahr"] + 1
    return df


def training_frame(
    features: pd.DataFrame, min_versicherte: float, max_abs_target: float
) -> pd.DataFrame:
    """Zeilen, die fürs Training taugen.

    Ausgeschlossen werden: kein Folgejahr, Kleinstversicherer und Strukturbrüche
    (Fusionen/Bestandesübertragungen mit |Ziel| > ``max_abs_target``).
    """
    mask = (
        features[TARGET].notna()
        & (features["versicherte"] >= min_versicherte)
        & (features[TARGET].abs() <= max_abs_target)
    )
    return features.loc[mask].reset_index(drop=True)


def sample_weight(frame: pd.DataFrame) -> pd.Series:
    """Grosse Versicherer zählen mehr, aber nicht linear (sonst dominiert ein Versicherer)."""
    weights: pd.Series = np.sqrt(frame["versicherte"])
    return weights


def pp_to_lever(prozentpunkte: float) -> float:
    """Prämienanpassung relativ zum Markt in %-Punkten -> log-Verhältnis (Feature-Skala)."""
    return float(np.log1p(prozentpunkte / 100.0))


def lever_to_pp(lever: float) -> float:
    return float(np.expm1(lever) * 100.0)
