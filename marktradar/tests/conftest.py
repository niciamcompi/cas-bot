"""Gemeinsame Test-Fixtures.

Die Tests laufen gegen eine *synthetische* Excel-Datei, die exakt wie die BAG-Datei
aufgebaut ist (Titelzeilen, Code-Zeile, Fusszeilen). Darin ist ein bekannter
Zusammenhang eingebaut: Wer die Prämie stärker erhöht als der Markt, verliert
Marktanteil. So können wir prüfen, ob die Pipeline ihn wiederfindet – ohne Netzwerk
und deterministisch.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
import pytest
import yaml

from marktradar.config import Settings, load_settings

CODES = ["0", None, "1", "3B", "5B", "13B", "12B", "4B", "6B", "7", "8B", "9B", "15", "4C", "6A"]
CODES += [None, "2", "14", "3A"]
YEARS = list(range(2006, 2016))
N_INSURERS = 30


def _simulate(seed: int = 0) -> dict[int, pd.DataFrame]:
    rng = np.random.default_rng(seed)
    bag_nrs = rng.choice(np.arange(10, 2000), N_INSURERS, replace=False)
    size = rng.lognormal(10.5, 1.2, N_INSURERS)
    rel_price = rng.normal(0, 0.06, N_INSURERS)
    reserves = rng.uniform(400, 1500, N_INSURERS)
    market_price = 2500.0
    sheets = {}
    for year in YEARS:
        price = market_price * np.exp(rel_price)
        rows = []
        for i in range(N_INSURERS):
            rows.append(
                {
                    "1": size[i],
                    "3B": price[i],
                    "5B": price[i] * 0.9,
                    "13B": 450.0,
                    "12B": price[i] * 0.9 + 450,
                    "4B": rng.normal(0, 200),
                    "6B": rng.uniform(120, 200),
                    "7": rng.normal(20, 50),
                    "8B": 600.0,
                    "9B": reserves[i],
                    "15": 0.9,
                    "4C": 0.0,
                    "6A": 0.05,
                    "2": size[i] * price[i] / 1e6,
                    "14": size[i] * price[i] / 1e6,
                    "3A": size[i] * price[i] / 1e6,
                }
            )
        sheets[year] = (bag_nrs, rows)
        # Dynamik ins nächste Jahr: Prämienschock -> Bestand reagiert (Elastizität -2)
        shock = rng.normal(0, 0.03, N_INSURERS)
        rel_price = rel_price + shock - np.average(rel_price + shock, weights=size)
        size = size * np.exp(-2.0 * shock + rng.normal(0, 0.005, N_INSURERS))
        market_price *= 1.04

    out = {}
    for year, (nrs, rows) in sheets.items():
        width = len(CODES)
        grid: list[list[object]] = [[None] * width for _ in range(9)]
        grid[1][0] = "T 5.01 Aufsichtsdaten OKP CH"
        grid[3][0], grid[3][1] = "BAG-", "Name des OKP Versicherers"
        grid.append([c if c is not None else None for c in CODES])
        for nr, values in zip(nrs, rows, strict=True):
            line: list[object] = [int(nr), f"Krankenkasse {nr}"]
            line += [values.get(c) if c else None for c in CODES[2:]]
            grid.append(line)
        grid.append([None] * width)
        grid.append(["Quelle und Erklärungen: T 5.02"] + [None] * (width - 1))
        out[year] = pd.DataFrame(grid)
    return out


@pytest.fixture(scope="session")
def workbook(tmp_path_factory: pytest.TempPathFactory) -> Path:
    path = tmp_path_factory.mktemp("raw") / "aufsichtsdaten.xlsx"
    with pd.ExcelWriter(path) as writer:
        pd.DataFrame([["Info"]]).to_excel(writer, sheet_name="info", header=False, index=False)
        for year, df in sorted(_simulate().items(), reverse=True):
            df.to_excel(writer, sheet_name=str(year), header=False, index=False)
            pd.DataFrame([["Erklärungen"]]).to_excel(
                writer, sheet_name=f"{year}_i", header=False, index=False
            )
    return path


@pytest.fixture
def settings(tmp_path: Path, workbook: Path) -> Settings:
    cfg = {
        "data": {
            "source_url": "https://example.invalid/data.xlsx",
            "raw_path": str(workbook),
            "processed_path": str(tmp_path / "panel.parquet"),
            "first_year": 2006,
        },
        "features": {"min_versicherte": 100, "max_abs_target": 0.5},
        "model": {"max_iter": 40, "min_samples_leaf": 10},
        "backtest": {"first_test_year": 2012},
        "registry": {"path": str(tmp_path / "models")},
    }
    path = tmp_path / "config" / "config.yaml"
    path.parent.mkdir()
    path.write_text(yaml.safe_dump(cfg))
    return load_settings(path)
