import pytest

from app.ingestion import who_mpox


SAMPLE_MPOX_RESPONSE = {
    "value": [
        {
            "COUNTRY": "United States of America",
            "DATE": "2026-09-27",
            "ISO3": "USA",
            "WHO_REGION": "AMRO",
            "TOTAL_CONF_CASES": 100,
            "TOTAL_PROB_CASES": 0,
            "TOTAL_CONF_DEATHS": 1,
            "NEW_CONF_CASES": 5,
            "NEW_PROB_CASES": 0,
            "NEW_CONF_DEATHS": 0,
        },
        {
            "COUNTRY": "Germany",
            "DATE": "2026-09-27",
            "ISO3": "DEU",
            "WHO_REGION": "EURO",
            "TOTAL_CONF_CASES": 50,
            "TOTAL_PROB_CASES": 0,
            "TOTAL_CONF_DEATHS": 0,
            "NEW_CONF_CASES": 2,
            "NEW_PROB_CASES": 0,
            "NEW_CONF_DEATHS": 0,
        },
    ]
}


@pytest.fixture
def patched_mpox(monkeypatch):
    async def _fake_fetch(url, timeout=120.0):
        return SAMPLE_MPOX_RESPONSE

    monkeypatch.setattr(who_mpox, "_fetch_json", _fake_fetch)


@pytest.mark.asyncio
async def test_fetch_who_mpox_new_cases(patched_mpox):
    snapshots = await who_mpox.fetch_who_mpox()
    new_cases = [s for s in snapshots if s["metric_name"] == "new_cases"]
    assert len(new_cases) == 2
    assert sum(s["metric_value"] for s in new_cases) == 7


@pytest.mark.asyncio
async def test_fetch_who_mpox_total_cases(patched_mpox):
    snapshots = await who_mpox.fetch_who_mpox()
    totals = [s for s in snapshots if s["metric_name"] == "cases"]
    assert len(totals) == 2
    assert sum(s["metric_value"] for s in totals) == 150


@pytest.mark.asyncio
async def test_fetch_who_mpox_empty_on_fetch_failure(monkeypatch):
    async def _fake_fetch(url, timeout=120.0):
        return {}

    monkeypatch.setattr(who_mpox, "_fetch_json", _fake_fetch)
    snapshots = await who_mpox.fetch_who_mpox()
    assert snapshots == []
