import pytest

from app.ingestion.cdc import fetch_cdc_dengue, fetch_cdc_mpox, fetch_cdc_nndss
from app.ingestion.common import canonical_condition_name
from app.ingestion.who import fetch_who_covid, fetch_who_don
from app.ingestion.ecdc import fetch_ecdc_respiratory


@pytest.mark.asyncio
async def test_fetch_cdc_nndss_parses_snapshot(monkeypatch):
    """CDC NNDSS adapter should normalize a Socrata response into OutbreakSnapshot dicts."""

    async def fake_get(self, url, **kwargs):
        class FakeResponse:
            def raise_for_status(self):
                pass

            def json(self):
                return [
                    {
                        "states": "California",
                        "year": "2024",
                        "week": "5",
                        "label": "Influenza A",
                        "m1": "12",
                        "m2": "3",
                        "m3": "0",
                        "m4": "0",
                        "sort_order": "20240500001",
                    }
                ]

        return FakeResponse()

    monkeypatch.setattr(
        "app.ingestion.cdc.httpx.AsyncClient.get",
        fake_get,
    )

    snapshots = await fetch_cdc_nndss(limit=10)

    assert len(snapshots) == 1
    snap = snapshots[0]
    assert snap["source"] == "cdc_nndss"
    assert snap["condition_name"] == "Influenza A"
    assert snap["state"] == "California"
    assert snap["country"] == "United States"
    assert snap["metric_name"] == "cases"
    assert snap["case_count"] == 12
    assert snap["source_id"].startswith("cdc_nndss:2024:5:California:Influenza A:")


@pytest.mark.asyncio
async def test_fetch_who_covid_parses_csv(monkeypatch):
    """WHO COVID-19 CSV adapter should normalize rows into snapshots."""

    csv_text = (
        "Date_reported,Country_code,Country,WHO_region,New_cases,Cumulative_cases,New_deaths,Cumulative_deaths\n"
        "2024-01-15,US,United States,AMRO,100,1000000,2,50000\n"
        "2024-01-15,CA,Canada,AMRO,50,500000,1,20000\n"
    )

    async def fake_fetch_who(url, timeout=120.0):
        return csv_text

    monkeypatch.setattr(
        "app.ingestion.who._fetch_csv",
        fake_fetch_who,
    )

    snapshots = await fetch_who_covid()

    assert len(snapshots) == 4  # new_cases + new_deaths for each country
    snap = next(s for s in snapshots if s["metric_name"] == "new_cases" and s["country"] == "United States")
    assert snap["source"] == "who_covid_cases"
    assert snap["condition_name"] == "COVID-19"
    assert snap["metric_value"] == 100.0
    assert snap["region_code"] == "US"
    assert snap["region_type"] == "country"


@pytest.mark.asyncio
async def test_fetch_ecdc_respiratory_parses_csv(monkeypatch):
    """ECDC respiratory CSV adapter should normalize rows into snapshots."""

    csv_text = (
        "countryname,yearweek,pathogen,pathogensubtype,indicator,value,age\n"
        "Germany,2024-W01,Influenza Virus,A(H1N1)pdm09,cases,42,all\n"
        "France,2024-W01,SARS-CoV-2,B.1.1.529,rate,12.5,all\n"
    )

    async def fake_fetch_ecdc(url, timeout=120.0):
        return csv_text

    monkeypatch.setattr(
        "app.ingestion.ecdc._fetch_csv",
        fake_fetch_ecdc,
    )

    snapshots = await fetch_ecdc_respiratory()

    assert len(snapshots) == 2
    germany = next(s for s in snapshots if s["country"] == "Germany")
    assert germany["source"] == "ecdc_respiratory"
    assert germany["condition_name"] == "Influenza A"
    assert germany["metric_name"] == "cases"
    assert germany["metric_value"] == 42.0
    assert germany["region_type"] == "country"


@pytest.mark.asyncio
async def test_fetch_cdc_mpox_parses_snapshot(monkeypatch):
    """CDC mpox wastewater adapter should normalize Socrata rows into snapshots."""

    async def fake_fetch_socrata(url, limit, where=None, order=None, timeout=60.0):
        return [
            {
                "state_territory": "ca",
                "counties_served": "Los Angeles",
                "site": "LA-1",
                "pcr_target": "hmpxv clade ii",
                "sample_collect_date": "2024-06-15",
                "pcr_target_avg_conc": "123.4",
            }
        ]

    monkeypatch.setattr(
        "app.ingestion.cdc._fetch_socrata_json",
        fake_fetch_socrata,
    )

    snapshots = await fetch_cdc_mpox(limit=10)

    assert len(snapshots) == 1
    snap = snapshots[0]
    assert snap["source"] == "cdc_mpox"
    assert snap["condition_name"] == "Mpox"
    assert snap["state"] == "ca"
    assert snap["county"] == "Los Angeles"
    assert snap["metric_name"] == "pcr_target_avg_conc"
    assert snap["metric_value"] == 123.4
    assert snap["source_id"].startswith("cdc_mpox:ca:Los Angeles:LA-1:")


@pytest.mark.asyncio
async def test_fetch_cdc_dengue_parses_snapshot(monkeypatch):
    """CDC dengue NNDSS adapter should filter and normalize rows into snapshots."""

    async def fake_fetch_socrata(url, limit, where=None, order=None, timeout=60.0):
        return [
            {
                "states": "Florida",
                "year": "2024",
                "week": "20",
                "label": "Dengue virus infections, Dengue",
                "m1": "1",
                "m2": "2",
                "m3": "3",
                "m4": "4",
                "sort_order": "20242001611",
            }
        ]

    monkeypatch.setattr(
        "app.ingestion.cdc._fetch_socrata_json",
        fake_fetch_socrata,
    )

    snapshots = await fetch_cdc_dengue(limit=10)

    assert len(snapshots) == 1
    snap = snapshots[0]
    assert snap["source"] == "cdc_dengue"
    assert snap["condition_name"] == "Dengue fever"
    assert snap["state"] == "Florida"
    assert snap["metric_name"] == "cases"
    assert snap["case_count"] == 3
    assert snap["source_id"].startswith("cdc_dengue:2024:20:Florida:")


@pytest.mark.asyncio
async def test_fetch_who_don_parses_alert(monkeypatch):
    """WHO DON adapter should normalize matching outbreak alerts into snapshots."""

    async def fake_fetch_who_don_json(url, params, timeout=60.0):
        return [
            {
                "Title": "Mpox - Sweden",
                "EmergencyEvent": {"Title": "Mpox"},
                "PublicationDate": "2024-08-30T14:16:08Z",
                "DonId": "2024-DON531",
                "UrlName": "2024-DON531",
                "ItemDefaultUrl": "/2024-DON531",
            },
            {
                "Title": "Dengue - Iran (Islamic Republic of)",
                "EmergencyEvent": {"Title": "Dengue"},
                "PublicationDate": "2024-07-22T08:35:12Z",
                "DonId": "2024-DON526",
                "UrlName": "2024-DON526",
                "ItemDefaultUrl": "/2024-DON526",
            },
            {
                "Title": "Ebola disease - Democratic Republic of the Congo",
                "EmergencyEvent": {"Title": "Ebola virus disease"},
                "PublicationDate": "2024-01-01T00:00:00Z",
                "DonId": "2024-DON001",
                "UrlName": "2024-DON001",
                "ItemDefaultUrl": "/2024-DON001",
            },
        ]

    monkeypatch.setattr(
        "app.ingestion.who._fetch_who_don_json",
        fake_fetch_who_don_json,
    )

    snapshots = await fetch_who_don(limit=10)

    assert len(snapshots) == 2
    mpox = next(s for s in snapshots if s["condition_name"] == "Mpox")
    assert mpox["source"] == "who_don"
    assert mpox["country"] == "Sweden"
    assert mpox["metric_name"] == "outbreak_alert"
    assert mpox["metric_value"] == 1.0
    dengue = next(s for s in snapshots if s["condition_name"] == "Dengue fever")
    assert dengue["country"] == "Iran (Islamic Republic of)"


def test_canonical_condition_name_normalizes_synonyms():
    """Raw source labels should map to canonical outbreak-intel names."""
    assert canonical_condition_name("Measles, Total") == "Measles"
    assert canonical_condition_name("Influenza A virus") == "Influenza A"
    assert canonical_condition_name("SARS-CoV-2") == "COVID-19"
    assert canonical_condition_name("Dengue virus infections, Dengue") == "Dengue fever"
    assert canonical_condition_name("Unknown exotic disease") == "Unknown exotic disease"


@pytest.mark.asyncio
async def test_fetch_who_don_matches_measles(monkeypatch):
    """WHO DON should now capture measles outbreak alerts."""

    async def fake_fetch_who_don_json(url, params, timeout=60.0):
        return [
            {
                "Title": "Measles - United States of America",
                "EmergencyEvent": {"Title": "Measles"},
                "PublicationDate": "2024-08-30T14:16:08Z",
                "DonId": "2024-DON999",
                "UrlName": "2024-DON999",
                "ItemDefaultUrl": "/2024-DON999",
            }
        ]

    monkeypatch.setattr(
        "app.ingestion.who._fetch_who_don_json",
        fake_fetch_who_don_json,
    )

    snapshots = await fetch_who_don(limit=10)
    assert len(snapshots) == 1
    assert snapshots[0]["condition_name"] == "Measles"
    assert snapshots[0]["country"] == "United States of America"
