"""REST-API (FastAPI).

Start lokal:  uv run marktradar serve
Doku:         http://localhost:8000/docs  (interaktiv, automatisch aus den Typen erzeugt)
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any

import pandas as pd
from fastapi import FastAPI, HTTPException, Query, Request
from pydantic import BaseModel, Field

from marktradar import __version__
from marktradar.config import Settings, load_settings
from marktradar.registry import load_production
from marktradar.service import ForecastService, UnknownInsurerError

PP_LIMIT = 15.0  # Szenarien ausserhalb ±15 %-Punkte liegen weit ausserhalb der Trainingsdaten


class PrognoseRequest(BaseModel):
    bag_nr: int = Field(..., examples=[8])
    praemienanpassung_rel_pp: float = Field(
        0.0,
        ge=-PP_LIMIT,
        le=PP_LIMIT,
        description="Prämienanpassung relativ zum Markt in %-Punkten "
        "(+2 = Prämie steigt 2 %-Punkte stärker als der Marktdurchschnitt).",
    )


class ElastizitaetRequest(BaseModel):
    bag_nr: int = Field(..., examples=[8])
    von_pp: float = Field(-5.0, ge=-PP_LIMIT, le=PP_LIMIT)
    bis_pp: float = Field(5.0, ge=-PP_LIMIT, le=PP_LIMIT)
    schritt_pp: float = Field(1.0, gt=0.1, le=5)


def create_app(settings: Settings | None = None) -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        cfg = settings or load_settings()
        model, metadata = load_production(cfg.registry.path)
        panel = pd.read_parquet(cfg.data.processed_path)
        app.state.service = ForecastService(
            model, panel, min_versicherte=cfg.features.min_versicherte
        )
        app.state.metadata = metadata
        yield

    app = FastAPI(
        title="Marktradar Krankenversicherung",
        version=__version__,
        description="Prognose der Marktanteilsentwicklung von Schweizer "
        "Krankenversicherern (OKP) auf Basis öffentlicher BAG-Aufsichtsdaten.",
        lifespan=lifespan,
    )

    def service(request: Request) -> ForecastService:
        svc: ForecastService = request.app.state.service
        return svc

    @app.get("/health")
    def health(request: Request) -> dict[str, Any]:
        return {"status": "ok", "modell_version": request.app.state.metadata["version"]}

    @app.get("/modell")
    def modell(request: Request) -> dict[str, Any]:
        """Version, Trainingsdaten und Backtest-Metriken des Produktionsmodells."""
        meta: dict[str, Any] = request.app.state.metadata
        return meta

    @app.get("/versicherer")
    def versicherer(request: Request) -> list[dict[str, Any]]:
        return service(request).versicherer()

    @app.post("/prognose")
    def prognose(body: PrognoseRequest, request: Request) -> dict[str, Any]:
        try:
            return service(request).prognose(body.bag_nr, body.praemienanpassung_rel_pp).as_dict()
        except UnknownInsurerError:
            raise HTTPException(404, f"Unbekannte BAG-Nr. {body.bag_nr}") from None

    @app.post("/elastizitaet")
    def elastizitaet(body: ElastizitaetRequest, request: Request) -> list[dict[str, Any]]:
        if body.von_pp >= body.bis_pp:
            raise HTTPException(422, "von_pp muss kleiner als bis_pp sein")
        try:
            return service(request).elastizitaet(
                body.bag_nr, body.von_pp, body.bis_pp, body.schritt_pp
            )
        except UnknownInsurerError:
            raise HTTPException(404, f"Unbekannte BAG-Nr. {body.bag_nr}") from None

    @app.get("/markt")
    def markt(
        request: Request,
        praemienanpassung_rel_pp: float = Query(0.0, ge=-PP_LIMIT, le=PP_LIMIT),
    ) -> list[dict[str, Any]]:
        """Alle Versicherer, sortiert nach prognostiziertem Marktanteilswachstum."""
        return service(request).markt(praemienanpassung_rel_pp)

    return app
