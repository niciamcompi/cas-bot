from pathlib import Path

import numpy as np
import pandas as pd
import pytest

from marktradar.data import parse_workbook
from marktradar.features import (
    FEATURES,
    LEVER,
    TARGET,
    build_features,
    lever_to_pp,
    pp_to_lever,
    training_frame,
)


@pytest.fixture
def feats(workbook: Path) -> pd.DataFrame:
    return build_features(parse_workbook(workbook))


def test_all_features_present(feats: pd.DataFrame) -> None:
    assert set(FEATURES) <= set(feats.columns)


def test_target_is_next_year_share_change(feats: pd.DataFrame) -> None:
    """Schutz gegen Data Leakage / Off-by-one: Ziel(t) = log-Anteil(t+1) - log-Anteil(t)."""
    one = feats[feats["bag_nr"] == feats["bag_nr"].iloc[0]].set_index("jahr")
    expected = one.loc[2008, "log_marktanteil"] - one.loc[2007, "log_marktanteil"]
    assert one.loc[2007, TARGET] == pytest.approx(expected)
    # Vorjahreswachstum in t+1 entspricht genau dem Ziel von t
    assert one.loc[2008, "anteilswachstum_vorjahr"] == pytest.approx(one.loc[2007, TARGET])


def test_last_year_has_no_target_and_no_lever(feats: pd.DataFrame) -> None:
    last = feats[feats["jahr"] == feats["jahr"].max()]
    assert last[TARGET].isna().all()
    assert last[LEVER].isna().all()


def test_market_relative_premium_is_centered(feats: pd.DataFrame) -> None:
    for _, g in feats.groupby("jahr"):
        ratio = np.exp(g["rel_praemie"])
        assert np.average(ratio, weights=g["versicherte"]) == pytest.approx(1.0)


def test_gap_years_break_the_chain(workbook: Path) -> None:
    panel = parse_workbook(workbook)
    nr = panel["bag_nr"].iloc[0]
    panel = panel[~((panel["bag_nr"] == nr) & (panel["jahr"] == 2010))]
    f = build_features(panel).set_index(["bag_nr", "jahr"])
    assert np.isnan(f.loc[(nr, 2009), TARGET])
    assert np.isnan(f.loc[(nr, 2011), "anteilswachstum_vorjahr"])


def test_training_frame_filters(feats: pd.DataFrame) -> None:
    tf = training_frame(feats, min_versicherte=0, max_abs_target=0.01)
    assert tf[TARGET].abs().le(0.01).all()
    assert tf[TARGET].notna().all()


@pytest.mark.parametrize("pp", [-5.0, 0.0, 2.5])
def test_pp_roundtrip(pp: float) -> None:
    assert lever_to_pp(pp_to_lever(pp)) == pytest.approx(pp)
