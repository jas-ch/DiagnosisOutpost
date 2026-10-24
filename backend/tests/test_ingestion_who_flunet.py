from datetime import datetime
from io import StringIO

import pytest

from app.ingestion import who_flunet


SAMPLE_FLUNET_CSV = """WHOREGION,FLUSEASON,HEMISPHERE,ITZ,COUNTRY_CODE,COUNTRY_AREA_TERRITORY,ISO_WEEKSTARTDATE,ISO_YEAR,ISO_WEEK,MMWR_WEEKSTARTDATE,MMWR_YEAR,MMWR_WEEK,ORIGIN_SOURCE,SPEC_PROCESSED_NB,SPEC_RECEIVED_NB,AH1N12009,AH1,AH3,AH5,AH7N9,ANOTSUBTYPED,ANOTSUBTYPABLE,AOTHER_SUBTYPE,AOTHER_SUBTYPE_DETAILS,INF_A,BVIC_2DEL,BVIC_3DEL,BVIC_NODEL,BVIC_DELUNK,BYAM,BNOTDETERMINED,INF_B,INF_ALL,INF_NEGATIVE,ILI_ACTIVITY,ADENO,BOCA,HUMAN_CORONA,METAPNEUMO,PARAINFLUENZA,RHINO,RSV_PROCESSED,RSV,OTHERRESPVIRUS,OTHER_RESPVIRUS_DETAILS,LAB_RESULT_COMMENT,WCR_COMMENT,ISO2,ISOYW,MMWRYW,PSOURCE_SUBTYPE_INF,PSOURCE_PPOS_INF,PSOURCE_RSV
AMR,YR,NH,FLU_CNT_AMC,USA,United States of America,2026-10-12,2026,42,2026-10-12,2026,42,NOTDEFINED,1000,,500,200,,,,,,,,700,,,,,,,,,,3,,,,,,,,150,,,,,,US,202642,202642,,,
EUR,YR,NH,FLU_EST_EUR,DEU,Germany,2026-10-12,2026,42,2026-10-12,2026,42,NOTDEFINED,800,,300,100,,,,,,,,400,,,,,,,,,,2,,,,,,,,80,,,,,,DE,202642,202642,,,
WPR,YR,NH,FLU_EST_WPR,JPN,Japan,2026-10-12,2026,42,2026-10-12,2026,42,NOTDEFINED,600,,200,50,,,,,,,,250,,,,,,,,,,1,,,,,,,,30,,,,,,JP,202642,202642,,,
"""


@pytest.fixture
def patched_flunet(monkeypatch):
    async def _fake_fetch(url, timeout=120.0):
        return SAMPLE_FLUNET_CSV

    monkeypatch.setattr(who_flunet, "_fetch_csv", _fake_fetch)


@pytest.mark.asyncio
async def test_fetch_who_flunet_influenza_a(patched_flunet):
    snapshots = await who_flunet.fetch_who_flunet()
    flu = [s for s in snapshots if s["condition_name"] == "Influenza A"]
    assert len(flu) == 3
    total = sum(s["metric_value"] for s in flu)
    assert total == 700 + 400 + 250
    assert all(s["metric_name"] == "cases" for s in flu)
    assert all(s["source"] == "who_flunet" for s in flu)


@pytest.mark.asyncio
async def test_fetch_who_flunet_rsv(patched_flunet):
    snapshots = await who_flunet.fetch_who_flunet()
    rsv = [s for s in snapshots if s["condition_name"] == "Respiratory Syncytial Virus"]
    assert len(rsv) == 3
    total = sum(s["metric_value"] for s in rsv)
    assert total == 150 + 80 + 30


@pytest.mark.asyncio
async def test_fetch_who_flunet_ari(patched_flunet):
    snapshots = await who_flunet.fetch_who_flunet()
    ari = [s for s in snapshots if s["condition_name"] == "Acute Respiratory Infection"]
    assert len(ari) == 3
    assert all(s["metric_name"] == "ili_activity" for s in ari)
    assert {s["metric_value"] for s in ari} == {3.0, 2.0, 1.0}


@pytest.mark.asyncio
async def test_fetch_who_flunet_empty_on_fetch_failure(monkeypatch):
    async def _fake_fetch(url, timeout=120.0):
        return ""

    monkeypatch.setattr(who_flunet, "_fetch_csv", _fake_fetch)
    snapshots = await who_flunet.fetch_who_flunet()
    assert snapshots == []
