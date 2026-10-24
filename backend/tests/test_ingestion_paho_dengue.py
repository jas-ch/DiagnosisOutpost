import pytest

from app.ingestion import paho_dengue


@pytest.mark.asyncio
async def test_fetch_paho_dengue_returns_empty(monkeypatch):
    """PAHO dengue portal is dashboard-based; the fetcher returns empty safely."""

    async def _fake_fetch(url, timeout=60.0):
        return "<html><body>Dengue indicators dashboard</body></html>"

    monkeypatch.setattr(paho_dengue, "_fetch_page", _fake_fetch)
    snapshots = await paho_dengue.fetch_paho_dengue()
    assert snapshots == []
