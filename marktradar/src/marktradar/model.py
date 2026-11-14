"""Modell, Training und zeitlich korrekter Backtest.

Modell: Gradient Boosting (scikit-learn ``HistGradientBoostingRegressor``)
- Punktprognose = Median (absoluter Fehler, robust gegen Ausreisser),
- zwei Quantil-Modelle für ein Prognoseintervall, das per *Conformal Prediction*
  nachkalibriert wird (siehe ``conformal_margin``),
- monotone Constraints für die Prämien-Features (siehe ``features.py``).

Bewusst *kein* exotisches Framework: scikit-learn ist stabil, gut dokumentiert und
überall installierbar. Das ist für Wartbarkeit wichtiger als die letzten 2 % Genauigkeit.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingRegressor

from marktradar.config import ModelConfig
from marktradar.features import (
    FEATURES,
    MONOTONIC_CONSTRAINTS,
    TARGET,
    sample_weight,
)


def _make_regressor(
    cfg: ModelConfig, loss: str, quantile: float | None = None
) -> HistGradientBoostingRegressor:
    kwargs: dict[str, object] = {}
    if quantile is not None:
        kwargs["quantile"] = quantile
    return HistGradientBoostingRegressor(
        loss=loss,
        learning_rate=cfg.learning_rate,
        max_iter=cfg.max_iter,
        max_depth=cfg.max_depth,
        min_samples_leaf=cfg.min_samples_leaf,
        l2_regularization=cfg.l2_regularization,
        monotonic_cst=MONOTONIC_CONSTRAINTS,
        random_state=cfg.random_state,
        **kwargs,
    )


@dataclass
class MarktradarModel:
    """Bündelt Punkt- und Intervallmodelle hinter einer einfachen ``predict``-API."""

    point: HistGradientBoostingRegressor
    lower: HistGradientBoostingRegressor
    upper: HistGradientBoostingRegressor
    features: list[str] = field(default_factory=lambda: list(FEATURES))
    # Zusätzliche Intervallbreite (beidseitig) aus der Conformal-Kalibrierung
    conformal_margin: float = 0.0

    def predict(self, X: pd.DataFrame) -> pd.DataFrame:
        X = X[self.features]
        point = self.point.predict(X)
        lo = self.lower.predict(X)
        hi = self.upper.predict(X)
        # Quantilmodelle sind unabhängig trainiert und können sich kreuzen -> sortieren.
        lo, hi = np.minimum(lo, point), np.maximum(hi, point)
        lo, hi = lo - self.conformal_margin, hi + self.conformal_margin
        return pd.DataFrame({"prognose": point, "untergrenze": lo, "obergrenze": hi}, index=X.index)


def fit(train: pd.DataFrame, cfg: ModelConfig, conformal_margin: float = 0.0) -> MarktradarModel:
    X, y, w = train[FEATURES], train[TARGET], sample_weight(train)
    q_lo, q_hi = cfg.quantiles
    return MarktradarModel(
        point=_make_regressor(cfg, "absolute_error").fit(X, y, sample_weight=w),
        lower=_make_regressor(cfg, "quantile", q_lo).fit(X, y, sample_weight=w),
        upper=_make_regressor(cfg, "quantile", q_hi).fit(X, y, sample_weight=w),
        conformal_margin=conformal_margin,
    )


def conformity_scores(pred: pd.DataFrame, y: pd.Series) -> np.ndarray:
    """Wie weit liegt der wahre Wert ausserhalb des Intervalls? (negativ = innerhalb)"""
    lower = pred["untergrenze"].to_numpy() - y.to_numpy()
    upper = y.to_numpy() - pred["obergrenze"].to_numpy()
    scores: np.ndarray = np.maximum(lower, upper)
    return scores


def conformal_margin(scores: np.ndarray, coverage: float) -> float:
    """Conformalized Quantile Regression (Romano et al., 2019).

    Quantilmodelle sind oft zu optimistisch (Intervalle zu schmal). Aus Fehlern auf
    *ungesehenen* Daten (Backtest) wird bestimmt, um wie viel das Intervall verbreitert
    werden muss, damit es die Zielabdeckung (z.B. 80 %) tatsächlich erreicht.
    """
    if len(scores) == 0:
        return 0.0
    n = len(scores)
    level = min(1.0, np.ceil((n + 1) * coverage) / n)
    return max(0.0, float(np.quantile(scores, level, method="higher")))


def _weighted_mae(err: pd.Series, w: pd.Series) -> float:
    return float(np.average(np.abs(err), weights=w))


def evaluate(pred: pd.DataFrame, actual: pd.DataFrame) -> dict[str, float]:
    """Metriken für ein Testjahr, alle mit sqrt(Bestand) gewichtet."""
    y, w = actual[TARGET], sample_weight(actual)
    momentum = actual["anteilswachstum_vorjahr"].fillna(0.0)
    inside = (y >= pred["untergrenze"]) & (y <= pred["obergrenze"])
    return {
        "mae_modell": _weighted_mae(pred["prognose"] - y, w),
        # Baseline 1: Marktanteil bleibt gleich (die ehrlichste "Nichts-tun"-Prognose)
        "mae_konstant": _weighted_mae(-y, w),
        # Baseline 2: Wachstum wie im Vorjahr
        "mae_vorjahr": _weighted_mae(momentum - y, w),
        # Für den Vertrieb zählt oft die Reihenfolge (wer gewinnt, wer verliert?)
        "rangkorrelation": float(pred["prognose"].corr(y, method="spearman")),
        "intervall_abdeckung": float(np.average(inside, weights=w)),
        "n": float(len(actual)),
    }


@dataclass
class BacktestResult:
    tabelle: pd.DataFrame  # Metriken pro Testjahr
    scores: np.ndarray  # Conformity-Scores aller Testjahre (für das finale Modell)


def backtest(frame: pd.DataFrame, cfg: ModelConfig, first_test_year: int) -> BacktestResult:
    """Rolling-origin Backtest: Für Testjahr T nur mit Basisjahren < T trainieren.

    So simuliert der Backtest exakt die reale Situation, in der man die Zukunft
    nicht kennt. Ein zufälliger Train/Test-Split würde hier Information aus der
    Zukunft ins Training schmuggeln und die Güte massiv überschätzen.

    Auch die Conformal-Kalibrierung ist zeitlich ehrlich: Für Testjahr T wird die
    Intervallbreite nur aus den Fehlern der Testjahre < T geschätzt.
    """
    coverage = cfg.quantiles[1] - cfg.quantiles[0]
    rows = []
    past_scores: list[np.ndarray] = []
    for year in sorted(y for y in frame["jahr"].unique() if y >= first_test_year):
        train = frame[frame["jahr"] < year]
        test = frame[frame["jahr"] == year]
        if len(train) < 50 or len(test) < 5:
            continue
        model = fit(train, cfg)
        raw = model.predict(test)
        prior = np.concatenate(past_scores) if past_scores else np.array([])
        model.conformal_margin = conformal_margin(prior, coverage)
        metrics = evaluate(model.predict(test), test)
        metrics["intervall_abdeckung_roh"] = evaluate(raw, test)["intervall_abdeckung"]
        rows.append({"basisjahr": int(year), **metrics})
        past_scores.append(conformity_scores(raw, test[TARGET]))
    if not rows:
        raise ValueError("Zu wenig Daten für einen Backtest")
    return BacktestResult(tabelle=pd.DataFrame(rows), scores=np.concatenate(past_scores))


def summarize_backtest(bt: pd.DataFrame) -> dict[str, float]:
    # Erstes Testjahr hat noch keine Kalibrierungsdaten -> für die Abdeckung weglassen
    s = bt.drop(columns=["basisjahr", "n"]).mean()
    s["intervall_abdeckung"] = bt["intervall_abdeckung"].iloc[1:].mean()
    summary = {str(k): round(float(v), 4) for k, v in s.items()}
    summary["verbesserung_vs_konstant"] = round(
        1 - summary["mae_modell"] / summary["mae_konstant"], 4
    )
    summary["testjahre"] = int(len(bt))
    return summary
