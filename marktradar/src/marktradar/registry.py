"""Minimale Modell-Registry auf dem Dateisystem.

    models/
      20261114-093012/          <- eine Version pro Trainingslauf
        model.joblib
        metadata.json           <- Metriken, Daten-Hash, Konfiguration, Git-Commit
      production.json           <- zeigt auf die produktive Version

Das ist bewusst simpel (kein MLflow-Server nötig), folgt aber denselben Ideen:
versionierte, unveränderliche Artefakte + ein Zeiger, der nur nach bestandener
Qualitätsprüfung umgesetzt wird. Rollback = Zeiger zurücksetzen.

Sicherheit: joblib/pickle führt beim Laden Code aus. Nur selbst erzeugte Artefakte laden.
"""

from __future__ import annotations

import json
import subprocess
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import joblib

from marktradar.model import MarktradarModel

PRODUCTION_POINTER = "production.json"


def _git_commit() -> str | None:
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],  # noqa: S607
            capture_output=True,
            text=True,
            check=True,
            cwd=Path(__file__).parent,
        )
        return out.stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def save(model: MarktradarModel, metadata: dict[str, Any], root: Path) -> Path:
    version = datetime.now(UTC).strftime("%Y%m%d-%H%M%S")
    target = root / version
    target.mkdir(parents=True, exist_ok=False)
    joblib.dump(model, target / "model.joblib")
    meta = {"version": version, "git_commit": _git_commit(), **metadata}
    (target / "metadata.json").write_text(
        json.dumps(meta, indent=2, ensure_ascii=False, default=str), encoding="utf-8"
    )
    return target


def promote(version: str, root: Path) -> None:
    if not (root / version / "model.joblib").exists():
        raise FileNotFoundError(f"Version {version} existiert nicht in {root}")
    (root / PRODUCTION_POINTER).write_text(
        json.dumps({"version": version}, indent=2), encoding="utf-8"
    )


def production_version(root: Path) -> str | None:
    pointer = root / PRODUCTION_POINTER
    if not pointer.exists():
        return None
    return str(json.loads(pointer.read_text(encoding="utf-8"))["version"])


def load_metadata(root: Path, version: str) -> dict[str, Any]:
    data: dict[str, Any] = json.loads(
        (root / version / "metadata.json").read_text(encoding="utf-8")
    )
    return data


def load_production(root: Path) -> tuple[MarktradarModel, dict[str, Any]]:
    version = production_version(root)
    if version is None:
        raise FileNotFoundError(
            f"Kein Produktionsmodell in {root}. Zuerst `marktradar train` ausführen."
        )
    model = joblib.load(root / version / "model.joblib")
    return model, load_metadata(root, version)


def should_promote(candidate_mae: float, production_mae: float | None, tolerance: float) -> bool:
    """Quality Gate: Kandidat darf höchstens ``tolerance`` (relativ) schlechter sein."""
    if production_mae is None:
        return True
    return candidate_mae <= production_mae * (1 + tolerance)
