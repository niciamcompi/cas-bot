"""Fachlogik für Prognosen und Szenarien – unabhängig von API oder CLI.

API und CLI rufen nur diese Klasse auf. So gibt es genau eine Stelle, an der
Prognosen berechnet werden, und sie lässt sich ohne Webserver testen.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np
import pandas as pd

from marktradar.features import LEVER, build_features, lever_to_pp, pp_to_lever
from marktradar.model import MarktradarModel


class UnknownInsurerError(KeyError):
    pass


@dataclass
class Prognose:
    bag_nr: int
    name: str
    basisjahr: int
    prognosejahr: int
    praemienanpassung_rel_pp: float
    marktanteil_basis_pct: float
    anteilswachstum_pct: float
    anteilswachstum_untergrenze_pct: float
    anteilswachstum_obergrenze_pct: float
    bestand_basis: int
    bestand_prognose: int

    def as_dict(self) -> dict[str, Any]:
        return self.__dict__.copy()


def _pct(log_change: float) -> float:
    return round(float(np.expm1(log_change) * 100), 2)


class ForecastService:
    def __init__(
        self, model: MarktradarModel, panel: pd.DataFrame, min_versicherte: float = 0
    ) -> None:
        self.model = model
        features = build_features(panel)
        self.basisjahr = int(features["jahr"].max())
        # Ausgangslage: letztes Datenjahr je Versicherer. Kleinstversicherer weglassen,
        # weil das Modell auf sie nicht trainiert wurde.
        latest = features[
            (features["jahr"] == self.basisjahr) & (features["versicherte"] >= min_versicherte)
        ]
        self.latest = latest.set_index("bag_nr")

    def versicherer(self) -> list[dict[str, Any]]:
        df = self.latest.sort_values("versicherte", ascending=False)
        return [
            {
                "bag_nr": int(str(bag_nr)),
                "name": row["name"],
                "versicherte": int(row["versicherte"]),
                "marktanteil_pct": round(float(np.exp(row["log_marktanteil"]) * 100), 2),
                "praemie_pp": round(float(row["praemie_pp"]), 0),
                "rel_praemie_pct": round(lever_to_pp(row["rel_praemie"]), 2),
            }
            for bag_nr, row in df.iterrows()
        ]

    def _row(self, bag_nr: int) -> pd.Series:
        if bag_nr not in self.latest.index:
            raise UnknownInsurerError(bag_nr)
        row: pd.Series = self.latest.loc[bag_nr]  # type: ignore[assignment]
        return row

    def prognose(self, bag_nr: int, praemienanpassung_rel_pp: float = 0.0) -> Prognose:
        """Prognose für einen Versicherer.

        ``praemienanpassung_rel_pp``: Wie viele Prozentpunkte die Prämie stärker (+)
        oder schwächer (-) steigt als der Markt. 0 = im Gleichschritt mit dem Markt.
        Annahme: Gesamtmarkt (Anzahl Versicherte) bleibt konstant.
        """
        row = self._row(bag_nr)
        X = row.to_frame().T.copy()
        X[LEVER] = pp_to_lever(praemienanpassung_rel_pp)
        X = X.astype({c: float for c in self.model.features})
        p = self.model.predict(X).iloc[0]
        bestand = float(row["versicherte"])
        return Prognose(
            bag_nr=int(bag_nr),
            name=str(row["name"]),
            basisjahr=self.basisjahr,
            prognosejahr=self.basisjahr + 1,
            praemienanpassung_rel_pp=praemienanpassung_rel_pp,
            marktanteil_basis_pct=round(float(np.exp(row["log_marktanteil"]) * 100), 3),
            anteilswachstum_pct=_pct(p["prognose"]),
            anteilswachstum_untergrenze_pct=_pct(p["untergrenze"]),
            anteilswachstum_obergrenze_pct=_pct(p["obergrenze"]),
            bestand_basis=round(bestand),
            bestand_prognose=round(bestand * float(np.exp(p["prognose"]))),
        )

    def elastizitaet(
        self, bag_nr: int, von_pp: float, bis_pp: float, schritt_pp: float
    ) -> list[dict[str, Any]]:
        """Prämien-Elastizitätskurve: Prognose über eine Spanne von Prämienszenarien."""
        steps = np.arange(von_pp, bis_pp + schritt_pp / 2, schritt_pp)
        return [self.prognose(bag_nr, round(float(s), 4)).as_dict() for s in steps]

    def markt(self, praemienanpassung_rel_pp: float = 0.0) -> list[dict[str, Any]]:
        """Prognose für alle Versicherer, sortiert nach erwartetem Wachstum."""
        result = [
            self.prognose(int(b), praemienanpassung_rel_pp).as_dict() for b in self.latest.index
        ]
        return sorted(result, key=lambda r: r["anteilswachstum_pct"], reverse=True)
