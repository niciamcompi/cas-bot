from pathlib import Path

import pandas as pd
import pytest

from marktradar.data import (
    REQUIRED_COLUMNS,
    DataValidationError,
    parse_sheet,
    parse_workbook,
    validate_panel,
)


def test_parse_workbook_reads_all_years(workbook: Path) -> None:
    panel = parse_workbook(workbook, first_year=2006)
    assert list(panel.columns) == REQUIRED_COLUMNS
    assert panel["jahr"].min() == 2006 and panel["jahr"].max() == 2015
    assert panel.groupby("jahr").size().eq(30).all()  # Fusszeilen wurden ignoriert
    validate_panel(panel)


def test_first_year_filter(workbook: Path) -> None:
    panel = parse_workbook(workbook, first_year=2012)
    assert panel["jahr"].min() == 2012


def test_missing_code_row_is_reported() -> None:
    sheet = pd.DataFrame([["Titel", None], ["foo", "bar"]])
    with pytest.raises(DataValidationError, match="Spaltencodes"):
        parse_sheet(sheet, 2020)


def test_missing_required_code_is_reported() -> None:
    sheet = pd.DataFrame([["0", None, "1", "3B"], [8, "CSS", 100, 3000]])
    with pytest.raises(DataValidationError, match="fehlen"):
        parse_sheet(sheet, 2020)


def test_validate_detects_duplicates(workbook: Path) -> None:
    panel = parse_workbook(workbook)
    broken = pd.concat([panel, panel.head(1)])
    with pytest.raises(DataValidationError, match="Doppelte"):
        validate_panel(broken)


def test_validate_detects_gaps(workbook: Path) -> None:
    panel = parse_workbook(workbook)
    with pytest.raises(DataValidationError, match="lückenlos"):
        validate_panel(panel[panel["jahr"] != 2010])
