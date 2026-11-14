"""End-to-End: CLI-Pipeline (build -> train) und danach die API darauf."""

import json
from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient
from typer.testing import CliRunner

from marktradar.api import create_app
from marktradar.cli import app as cli
from marktradar.config import Settings

runner = CliRunner()


@pytest.fixture
def trained(settings: Settings) -> Settings:
    config = str(settings.registry.path.parent / "config" / "config.yaml")
    for cmd in (["build"], ["train"]):
        result = runner.invoke(cli, [*cmd, "--config", config])
        assert result.exit_code == 0, result.output
    return settings


@pytest.fixture
def client(trained: Settings) -> Iterator[TestClient]:
    with TestClient(create_app(trained)) as c:
        yield c


def test_quality_gate_blocks_worse_model(trained: Settings) -> None:
    from marktradar import registry

    root = trained.registry.path
    prod = registry.production_version(root)
    assert prod is not None
    # Produktionsmodell künstlich "besser" machen -> neues Modell muss abgelehnt werden
    meta_path = root / prod / "metadata.json"
    meta = json.loads(meta_path.read_text())
    meta["backtest"]["mae_modell"] = 1e-9
    meta_path.write_text(json.dumps(meta))
    config = str(root.parent / "config" / "config.yaml")
    result = runner.invoke(cli, ["train", "--config", config])
    assert result.exit_code == 2, result.output
    assert registry.production_version(root) == prod


def test_health_and_model(client: TestClient) -> None:
    assert client.get("/health").json()["status"] == "ok"
    meta = client.get("/modell").json()
    assert "backtest" in meta and meta["features"]


def test_versicherer_list(client: TestClient) -> None:
    rows = client.get("/versicherer").json()
    assert len(rows) == 30
    assert rows[0]["versicherte"] >= rows[-1]["versicherte"]


def test_prognose(client: TestClient) -> None:
    bag_nr = client.get("/versicherer").json()[0]["bag_nr"]
    r = client.post("/prognose", json={"bag_nr": bag_nr, "praemienanpassung_rel_pp": 2})
    assert r.status_code == 200
    body = r.json()
    assert body["prognosejahr"] == body["basisjahr"] + 1 == 2016
    lo, mid, hi = (
        body["anteilswachstum_untergrenze_pct"],
        body["anteilswachstum_pct"],
        body["anteilswachstum_obergrenze_pct"],
    )
    assert lo <= mid <= hi


def test_elastizitaet_is_monotone(client: TestClient) -> None:
    bag_nr = client.get("/versicherer").json()[0]["bag_nr"]
    curve = client.post("/elastizitaet", json={"bag_nr": bag_nr}).json()
    growth = [p["anteilswachstum_pct"] for p in curve]
    assert len(growth) == 11
    assert growth == sorted(growth, reverse=True)


def test_markt_sorted(client: TestClient) -> None:
    rows = client.get("/markt").json()
    growth = [r["anteilswachstum_pct"] for r in rows]
    assert growth == sorted(growth, reverse=True)


def test_errors(client: TestClient) -> None:
    assert client.post("/prognose", json={"bag_nr": 999999}).status_code == 404
    too_big = {"bag_nr": 8, "praemienanpassung_rel_pp": 50}
    assert client.post("/prognose", json=too_big).status_code == 422
    bad_range = {"bag_nr": 8, "von_pp": 3, "bis_pp": 1}
    assert client.post("/elastizitaet", json=bad_range).status_code == 422
