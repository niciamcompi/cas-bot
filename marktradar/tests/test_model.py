from pathlib import Path

import numpy as np
import pandas as pd
import pytest

from marktradar.config import ModelConfig
from marktradar.data import parse_workbook
from marktradar.features import LEVER, TARGET, build_features, training_frame
from marktradar.model import backtest, conformal_margin, fit, summarize_backtest

CFG = ModelConfig(max_iter=80, min_samples_leaf=10)


@pytest.fixture(scope="module")
def frame(workbook: Path) -> pd.DataFrame:
    return training_frame(build_features(parse_workbook(workbook)), 100, 0.5)


def test_model_learns_premium_effect(frame: pd.DataFrame) -> None:
    model = fit(frame, CFG)
    X = frame.head(20).copy()
    low = model.predict(X.assign(**{LEVER: -0.05}))["prognose"]
    high = model.predict(X.assign(**{LEVER: 0.05}))["prognose"]
    assert (high <= low).all()  # monotone Constraint
    assert (low - high).mean() > 0.05  # simulierte Elastizität ist -2


def test_interval_contains_point(frame: pd.DataFrame) -> None:
    pred = fit(frame, CFG, conformal_margin=0.01).predict(frame)
    assert (pred["untergrenze"] <= pred["prognose"]).all()
    assert (pred["prognose"] <= pred["obergrenze"]).all()


def test_backtest_is_out_of_time_and_beats_baseline(frame: pd.DataFrame) -> None:
    result = backtest(frame, CFG, first_test_year=2011)
    bt = result.tabelle
    assert bt["basisjahr"].tolist() == sorted(bt["basisjahr"])
    assert bt["basisjahr"].min() == 2011
    summary = summarize_backtest(bt)
    assert summary["mae_modell"] < summary["mae_konstant"]
    assert len(result.scores) == int(bt["n"].sum())


def test_backtest_never_trains_on_test_year(
    frame: pd.DataFrame, monkeypatch: pytest.MonkeyPatch
) -> None:
    import marktradar.model as m

    seen: list[tuple[int, int]] = []
    real_fit = m.fit

    def spy(
        train: pd.DataFrame, cfg: ModelConfig, conformal_margin: float = 0.0
    ) -> m.MarktradarModel:
        seen.append((int(train["jahr"].max()), len(train)))
        return real_fit(train, cfg, conformal_margin)

    monkeypatch.setattr(m, "fit", spy)
    bt = m.backtest(frame, CFG, first_test_year=2012).tabelle
    for (max_train_year, _), test_year in zip(seen, bt["basisjahr"], strict=True):
        assert max_train_year < test_year


def test_conformal_margin() -> None:
    scores = np.linspace(-1, 1, 101)
    # Endliche-Stichproben-Korrektur: etwas mehr als das 80 %-Quantil (0.6)
    assert 0.6 <= conformal_margin(scores, 0.8) <= 0.66
    assert conformal_margin(np.array([-1.0, -0.5]), 0.5) == 0.0  # nie negativ
    assert conformal_margin(np.array([]), 0.8) == 0.0


def test_target_not_used_as_feature(frame: pd.DataFrame) -> None:
    model = fit(frame, CFG)
    assert TARGET not in model.features
