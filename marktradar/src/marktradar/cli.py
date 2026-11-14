"""Kommandozeile: ``uv run marktradar --help``

Typischer Ablauf (= die ML-Pipeline):
    marktradar download   # Rohdaten vom BAG holen
    marktradar build      # parsen + validieren -> data/processed/panel.parquet
    marktradar train      # Backtest, finales Training, Quality Gate, Registry
    marktradar predict 8 --pp 2
    marktradar serve
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Annotated, Any

import pandas as pd
import typer

from marktradar import data, registry
from marktradar.config import Settings, load_settings
from marktradar.features import FEATURES, build_features, training_frame
from marktradar.model import backtest, conformal_margin, fit, summarize_backtest
from marktradar.service import ForecastService

app = typer.Typer(help="Marktradar: Marktanteilsprognose für Krankenversicherer.")
ConfigOpt = Annotated[Path | None, typer.Option("--config", "-c", help="Pfad zu config.yaml")]


def _settings(config: Path | None) -> Settings:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    return load_settings(config)


def _echo_json(obj: Any) -> None:
    typer.echo(json.dumps(obj, indent=2, ensure_ascii=False))


@app.command()
def download(config: ConfigOpt = None) -> None:
    """Rohdaten (BAG Aufsichtsdaten OKP) herunterladen."""
    cfg = _settings(config)
    digest = data.download(cfg.data.source_url, cfg.data.raw_path, cfg.data.sha256)
    typer.echo(f"Gespeichert: {cfg.data.raw_path} (sha256 {digest[:12]}...)")


@app.command()
def build(config: ConfigOpt = None) -> None:
    """Rohdaten parsen, validieren und als Parquet speichern."""
    cfg = _settings(config)
    panel = data.parse_workbook(cfg.data.raw_path, cfg.data.first_year)
    data.validate_panel(panel)
    cfg.data.processed_path.parent.mkdir(parents=True, exist_ok=True)
    panel.to_parquet(cfg.data.processed_path, index=False)
    years = f"{panel['jahr'].min()}–{panel['jahr'].max()}"
    typer.echo(f"{len(panel)} Zeilen, {panel['bag_nr'].nunique()} Versicherer, {years}")


def _load_training(cfg: Settings) -> pd.DataFrame:
    panel = pd.read_parquet(cfg.data.processed_path)
    feats = build_features(panel)
    return training_frame(feats, cfg.features.min_versicherte, cfg.features.max_abs_target)


@app.command("backtest")
def backtest_cmd(config: ConfigOpt = None) -> None:
    """Nur den zeitlichen Backtest rechnen und ausgeben (nichts speichern)."""
    cfg = _settings(config)
    bt = backtest(_load_training(cfg), cfg.model, cfg.backtest.first_test_year).tabelle
    typer.echo(bt.round(4).to_string(index=False))
    _echo_json(summarize_backtest(bt))


@app.command()
def train(
    config: ConfigOpt = None,
    force: Annotated[bool, typer.Option(help="Quality Gate ignorieren")] = False,
) -> None:
    """Backtest + finales Training + Quality Gate + Ablage in der Registry."""
    cfg = _settings(config)
    frame = _load_training(cfg)
    result = backtest(frame, cfg.model, cfg.backtest.first_test_year)
    bt = result.tabelle
    summary = summarize_backtest(bt)
    coverage = cfg.model.quantiles[1] - cfg.model.quantiles[0]
    margin = conformal_margin(result.scores, coverage)
    model = fit(frame, cfg.model, conformal_margin=margin)

    raw_hash = data.sha256_of(cfg.data.raw_path) if cfg.data.raw_path.exists() else None
    metadata = {
        "trainiert_auf_basisjahre": [
            int(frame["jahr"].min()),
            int(frame["jahr"].max()),
        ],
        "n_trainingszeilen": len(frame),
        "features": FEATURES,
        "backtest": summary,
        "conformal_margin": round(margin, 5),
        "backtest_pro_jahr": bt.round(4).to_dict(orient="records"),
        "daten_sha256": raw_hash,
        "daten_quelle": cfg.data.source_url,
        "konfiguration": cfg.model.model_dump(),
    }
    root = cfg.registry.path
    version_dir = registry.save(model, metadata, root)
    _echo_json(summary)

    prod = registry.production_version(root)
    prod_mae = registry.load_metadata(root, prod)["backtest"]["mae_modell"] if prod else None
    if force or registry.should_promote(
        summary["mae_modell"], prod_mae, cfg.registry.promotion_tolerance
    ):
        registry.promote(version_dir.name, root)
        typer.echo(f"OK: Version {version_dir.name} ist jetzt produktiv.")
    else:
        typer.echo(
            f"ABGELEHNT: Version {version_dir.name} gespeichert, aber NICHT produktiv: "
            f"MAE {summary['mae_modell']} vs. Produktion {prod_mae}."
        )
        raise typer.Exit(code=2)


@app.command()
def promote(version: str, config: ConfigOpt = None) -> None:
    """Eine bestimmte Version produktiv setzen (z.B. Rollback)."""
    cfg = _settings(config)
    registry.promote(version, cfg.registry.path)
    typer.echo(f"Version {version} ist jetzt produktiv.")


@app.command()
def predict(
    bag_nr: int,
    pp: Annotated[
        float, typer.Option(help="Prämienanpassung relativ zum Markt in %-Punkten")
    ] = 0.0,
    kurve: Annotated[bool, typer.Option(help="Elastizitätskurve -5..+5 %-Punkte")] = False,
    config: ConfigOpt = None,
) -> None:
    """Prognose für einen Versicherer (BAG-Nr., z.B. 8 = CSS)."""
    cfg = _settings(config)
    model, _ = registry.load_production(cfg.registry.path)
    svc = ForecastService(
        model,
        pd.read_parquet(cfg.data.processed_path),
        min_versicherte=cfg.features.min_versicherte,
    )
    if kurve:
        rows = svc.elastizitaet(bag_nr, -5, 5, 1)
        cols = ["praemienanpassung_rel_pp", "anteilswachstum_pct", "bestand_prognose"]
        typer.echo(pd.DataFrame(rows)[cols].to_string(index=False))
    else:
        _echo_json(svc.prognose(bag_nr, pp).as_dict())


@app.command()
def serve(
    host: str = "0.0.0.0",  # noqa: S104 - im Container gewollt
    port: int = 8000,
    config: ConfigOpt = None,
) -> None:
    """REST-API starten."""
    import uvicorn

    from marktradar.api import create_app

    uvicorn.run(create_app(_settings(config)), host=host, port=port)


if __name__ == "__main__":
    app()
