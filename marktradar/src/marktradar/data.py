"""Daten beschaffen, parsen und prüfen.

Quelle: BAG, Statistik der obligatorischen Krankenversicherung, Tabelle T 5.01
"Aufsichtsdaten OKP" (ein Excel-Blatt pro Jahr, ein Versicherer pro Zeile).

Die Spaltenüberschriften ändern sich über die Jahre, aber jede Tabelle hat eine
Zeile mit stabilen Spaltencodes (``1`` = Versichertenbestand, ``3B`` = Prämie je
versicherte Person, ...). Der Parser orientiert sich nur an diesen Codes und ist
dadurch robust gegen Layout-Änderungen.
"""

from __future__ import annotations

import hashlib
import logging
from pathlib import Path

import httpx
import pandas as pd

from marktradar import __version__

log = logging.getLogger(__name__)

# BAG-Spaltencode -> unser Spaltenname (Definitionen: Blatt "<jahr>_i" der Quelldatei)
COLUMN_CODES: dict[str, str] = {
    "1": "versicherte",  # durchschnittlicher Versichertenbestand
    "3A": "praemien_mio",  # Prämiensoll in Mio. Fr.
    "3B": "praemie_pp",  # Prämiensoll je versicherte Person in Fr.
    "4B": "risikoausgleich_pp",  # Risikoausgleich je Person (+ = erhält, - = zahlt ein)
    "5B": "nettoleistungen_pp",  # Nettoleistungen je Person
    "6B": "verwaltung_pp",  # Verwaltungsaufwand je Person
    "7": "ergebnis_pp",  # Gesamtergebnis je Person
    "9B": "reserven_pp",  # Reserven je Person
    "15": "leistungsquote",  # Nettoleistungen / Prämien
}
REQUIRED_COLUMNS = ["bag_nr", "name", "jahr", *COLUMN_CODES.values()]


class DataValidationError(ValueError):
    """Die Daten erfüllen die erwarteten Annahmen nicht."""


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download(url: str, dest: Path, expected_sha256: str | None = None) -> str:
    """Datei herunterladen (atomar) und SHA-256 zurückgeben.

    Ein abweichender Hash ist kein Fehler (das BAG aktualisiert die Datei), wird aber
    laut geloggt: so merkst du, dass sich die Datenbasis verändert hat.
    """
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    h = hashlib.sha256()
    headers = {"User-Agent": f"marktradar/{__version__} (open-data research client)"}
    with httpx.stream("GET", url, headers=headers, follow_redirects=True, timeout=60) as response:
        response.raise_for_status()
        with tmp.open("wb") as f:
            for chunk in response.iter_bytes():
                f.write(chunk)
                h.update(chunk)
    tmp.replace(dest)
    digest = h.hexdigest()
    if expected_sha256 and digest != expected_sha256:
        log.warning(
            "SHA-256 weicht ab (erwartet %s, erhalten %s): neue Datenversion?",
            expected_sha256,
            digest,
        )
    return digest


def _find_code_row(sheet: pd.DataFrame, max_rows: int = 20) -> int:
    for i in range(min(max_rows, len(sheet))):
        if str(sheet.iloc[i, 0]).strip() == "0":
            return i
    raise DataValidationError("Keine Zeile mit Spaltencodes gefunden")


def _normalise_code(value: object) -> str:
    text = str(value).strip()
    return text.removesuffix(".0")


def parse_sheet(sheet: pd.DataFrame, year: int) -> pd.DataFrame:
    """Ein Jahresblatt (ohne Header eingelesen) in eine saubere Tabelle umwandeln."""
    code_row = _find_code_row(sheet)
    codes = [_normalise_code(c) for c in sheet.iloc[code_row]]
    missing = set(COLUMN_CODES) - set(codes)
    if missing:
        raise DataValidationError(f"Jahr {year}: Spaltencodes fehlen: {sorted(missing)}")

    body = sheet.iloc[code_row + 1 :]
    out = pd.DataFrame(
        {
            "bag_nr": pd.to_numeric(body.iloc[:, 0], errors="coerce"),
            "name": body.iloc[:, 1].astype(str).str.strip(),
        }
    )
    for idx, code in enumerate(codes):
        if code in COLUMN_CODES:
            out[COLUMN_CODES[code]] = pd.to_numeric(body.iloc[:, idx], errors="coerce")

    # Fusszeilen und Leerzeilen haben keine numerische BAG-Nr.
    out = out[out["bag_nr"].notna() & (out["versicherte"] > 0)].copy()
    out["bag_nr"] = out["bag_nr"].astype(int)
    out["jahr"] = year
    return out[REQUIRED_COLUMNS].reset_index(drop=True)


def parse_workbook(path: Path, first_year: int = 2006) -> pd.DataFrame:
    """Alle Jahresblätter ab ``first_year`` zu einem Panel (Versicherer x Jahr) zusammenfügen."""
    book = pd.ExcelFile(path)
    frames = []
    for name in book.sheet_names:
        if not str(name).isdigit() or int(name) < first_year:
            continue
        sheet = pd.read_excel(book, sheet_name=name, header=None)
        frames.append(parse_sheet(sheet, int(name)))
    if not frames:
        raise DataValidationError(f"Keine Jahresblätter ab {first_year} gefunden")
    panel = pd.concat(frames, ignore_index=True)
    return panel.sort_values(["bag_nr", "jahr"]).reset_index(drop=True)


def validate_panel(panel: pd.DataFrame) -> None:
    """Fachliche Plausibilitätsprüfungen. Wirft ``DataValidationError``."""
    errors: list[str] = []
    missing = set(REQUIRED_COLUMNS) - set(panel.columns)
    if missing:
        errors.append(f"Spalten fehlen: {sorted(missing)}")
    else:
        if panel.duplicated(["bag_nr", "jahr"]).any():
            errors.append("Doppelte Einträge (bag_nr, jahr)")
        if (panel["versicherte"] <= 0).any():
            errors.append("Versichertenbestand <= 0")
        if panel["praemie_pp"].isna().any() or (panel["praemie_pp"] <= 0).any():
            errors.append("Prämie je Person fehlt oder <= 0")
        years = sorted(panel["jahr"].unique())
        if years != list(range(years[0], years[-1] + 1)):
            errors.append(f"Jahre nicht lückenlos: {years}")
        # Grobe Plausibilität: OKP-Durchschnittsprämie liegt seit 2006 zwischen 1000 und 8000 Fr.
        avg = (panel["praemie_pp"] * panel["versicherte"]).groupby(panel["jahr"]).sum()
        avg = avg / panel.groupby("jahr")["versicherte"].sum()
        if ((avg < 1000) | (avg > 8000)).any():
            errors.append("Unplausible Marktdurchschnittsprämie")
    if errors:
        raise DataValidationError("; ".join(errors))
