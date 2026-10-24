from io import BytesIO

import openpyxl
import pytest

from app.ingestion import who_measles


def _make_measles_workbook() -> bytes:
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "WEB"
    ws.append(
        (
            "Region",
            "Country",
            "ISO3",
            "Year",
            "Month",
            "Measles \nsuspect",
            "Measles \nclinical",
            "Measles \nepi-linked",
            "Measles \nlab-confirmed",
            "Measles \ntotal",
        )
    )
    ws.append(("AFR", "Nigeria", "NGA", "2026", "09", "100", "50", "20", "30", 100))
    ws.append(("EUR", "Germany", "DEU", "2026", "09", "10", "5", "2", "3", 10))
    ws.append(("AMR", "United States of America", "USA", "2026", "09", "5", "2", "1", "2", 5))
    buffer = BytesIO()
    wb.save(buffer)
    return buffer.getvalue()


@pytest.fixture
def patched_measles(monkeypatch):
    async def _fake_fetch(url, timeout=120.0):
        return _make_measles_workbook()

    monkeypatch.setattr(who_measles, "_fetch_xlsx", _fake_fetch)


@pytest.mark.asyncio
async def test_fetch_who_measles_totals(patched_measles):
    snapshots = await who_measles.fetch_who_measles()
    assert len(snapshots) == 3
    assert all(s["condition_name"] == "Measles" for s in snapshots)
    assert all(s["metric_name"] == "cases" for s in snapshots)
    assert sum(s["metric_value"] for s in snapshots) == 115


@pytest.mark.asyncio
async def test_fetch_who_measles_empty_on_fetch_failure(monkeypatch):
    async def _fake_fetch(url, timeout=120.0):
        return b""

    monkeypatch.setattr(who_measles, "_fetch_xlsx", _fake_fetch)
    snapshots = await who_measles.fetch_who_measles()
    assert snapshots == []
