def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "app": "Diagnosis Outpost Backend"}


def test_outbreaks_empty(client):
    response = client.get("/outbreaks")
    assert response.status_code == 200
    assert response.json() == []


def test_outbreaks_limit(client):
    # Seed two snapshots directly into the test database.
    from app.database import SessionLocal
    from app import models

    db = SessionLocal()
    try:
        db.add_all(
            [
                models.OutbreakSnapshot(
                    source="test",
                    source_id="test:1",
                    condition_name="Influenza A",
                    state="California",
                ),
                models.OutbreakSnapshot(
                    source="test",
                    source_id="test:2",
                    condition_name="COVID-19",
                    state="California",
                ),
            ]
        )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks?limit=1")
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1

    response = client.get("/outbreaks")
    assert response.status_code == 200
    assert len(response.json()) == 2


def test_outbreaks_filter_by_state(client):
    from app.database import SessionLocal
    from app import models

    db = SessionLocal()
    try:
        db.add_all(
            [
                models.OutbreakSnapshot(
                    source="test",
                    source_id="test:ca",
                    condition_name="Influenza A",
                    state="California",
                ),
                models.OutbreakSnapshot(
                    source="test",
                    source_id="test:ny",
                    condition_name="Influenza A",
                    state="New York",
                ),
            ]
        )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks?state=California")
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1
    assert data[0]["state"] == "California"


def test_create_signal(client):
    payload = {
        "anonymous_id": "anon-123",
        "country": "United States",
        "state": "California",
        "county": "San Diego",
        "symptom_summary": "fever and cough",
        "risk_level": "moderate",
    }
    response = client.post("/signals", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["anonymous_id"] == "anon-123"
    assert data["risk_level"] == "moderate"


def test_signals_aggregate(client):
    payload = {
        "anonymous_id": "anon-1",
        "state": "California",
        "risk_level": "low",
    }
    response = client.post("/signals", json=payload)
    assert response.status_code == 200

    payload["anonymous_id"] = "anon-2"
    payload["risk_level"] = "moderate"
    response = client.post("/signals", json=payload)
    assert response.status_code == 200

    response = client.get("/signals/aggregate?state=California")
    assert response.status_code == 200
    data = response.json()
    assert data["count"] == 2
    assert data["by_risk_level"] == {"low": 1, "moderate": 1}


def test_admin_ingest_without_secret(client):
    response = client.post("/admin/ingest")
    assert response.status_code == 403
    assert response.json()["detail"] == "Invalid ingest secret"


def test_admin_ingest_with_secret(client, monkeypatch):
    import app.main as main_module

    # Patch ingest_all to avoid real network calls.
    captured_sources = []

    async def fake_ingest_all(limit_per_source: int = 5000, sources=None):
        captured_sources.append(sources)
        return [
            {
                "source": "test",
                "source_id": "test:ingest-1",
                "condition_name": "Test Condition",
                "metric_name": "cases",
                "metric_value": 10,
            }
        ]

    monkeypatch.setattr(main_module, "ingest_all", fake_ingest_all)

    response = client.post("/admin/ingest", headers={"X-Ingest-Secret": "test-secret"})
    assert response.status_code == 200
    data = response.json()
    assert data["ingested"] == 1
    assert data["by_source"] == {"test": 1}
    assert captured_sources[-1] is None


def test_admin_ingest_source_specific(client, monkeypatch):
    import app.main as main_module

    captured_sources = []

    async def fake_ingest_all(limit_per_source: int = 5000, sources=None):
        captured_sources.append(sources)
        return [
            {
                "source": sources[0] if sources else "test",
                "source_id": "test:ingest-1",
                "condition_name": "Test Condition",
                "metric_name": "cases",
                "metric_value": 10,
            }
        ]

    monkeypatch.setattr(main_module, "ingest_all", fake_ingest_all)

    response = client.post(
        "/admin/ingest?source=cdc_nndss,who_covid",
        headers={"X-Ingest-Secret": "test-secret"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["ingested"] == 1
    assert captured_sources[-1] == ["cdc_nndss", "who_covid"]


def test_admin_ingest_unknown_source(client):
    response = client.post(
        "/admin/ingest?source=not_a_source",
        headers={"X-Ingest-Secret": "test-secret"},
    )
    assert response.status_code == 400
    assert "not_a_source" in response.json()["detail"]


def test_outbreaks_recent_returns_all_sources(client):
    from datetime import datetime, timedelta
    from app.database import SessionLocal
    from app import models

    db = SessionLocal()
    try:
        db.add_all(
            [
                models.OutbreakSnapshot(
                    source="cdc_measles",
                    source_id="cdc_measles:1",
                    condition_name="Measles",
                    country="United States",
                    state="California",
                    region_type="state",
                    case_count=10,
                    report_date=datetime.utcnow() - timedelta(days=1),
                ),
                models.OutbreakSnapshot(
                    source="who_covid_cases",
                    source_id="who_covid_cases:1",
                    condition_name="COVID-19",
                    country="Canada",
                    region_type="country",
                    metric_name="new_cases",
                    metric_value=50,
                    report_date=datetime.utcnow() - timedelta(days=1),
                ),
            ]
        )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks/recent?days=30&limit=100")
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 2
    sources = {row["source"] for row in data}
    assert sources == {"cdc_measles", "who_covid_cases"}


def test_outbreaks_aggregate_sums_subcategories(client):
    """National rows with subcategory labels are summed, not double-counted."""
    from datetime import datetime, timedelta
    from app.database import SessionLocal
    from app import models

    latest = datetime.utcnow() - timedelta(days=1)
    prior = datetime.utcnow() - timedelta(days=8)

    db = SessionLocal()
    try:
        db.add_all(
            [
                models.OutbreakSnapshot(
                    source="cdc_measles",
                    source_id="cdc_measles:us:imported:40",
                    condition_name="Measles",
                    country="United States",
                    region="U.S. Residents",
                    region_type="country",
                    case_count=68,
                    weekly_count=0,
                    report_date=latest,
                ),
                models.OutbreakSnapshot(
                    source="cdc_measles",
                    source_id="cdc_measles:us:indigenous:40",
                    condition_name="Measles",
                    country="United States",
                    region="U.S. Residents",
                    region_type="country",
                    case_count=4008,
                    weekly_count=224,
                    report_date=latest,
                ),
                models.OutbreakSnapshot(
                    source="cdc_measles",
                    source_id="cdc_measles:us:indigenous:39",
                    condition_name="Measles",
                    country="United States",
                    region="U.S. Residents",
                    region_type="country",
                    case_count=3714,
                    weekly_count=140,
                    report_date=prior,
                ),
            ]
        )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks/aggregate")
    assert response.status_code == 200
    data = response.json()
    measles = data["diseases"]["Measles"]
    assert measles["us"]["ytd"] == 4076
    assert measles["us"]["weekly_new"] == 224
    assert measles["us"]["weekly_change"] == 84
    assert measles["us"]["ytd_label"] == "YTD"


def test_outbreaks_aggregate_global_covid(client):
    """Global COVID block returns the latest meaningful weekly snapshot."""
    from datetime import datetime, timedelta
    from app.database import SessionLocal
    from app import models

    db = SessionLocal()
    latest = datetime.utcnow() - timedelta(days=1)
    prior = datetime.utcnow() - timedelta(days=8)
    try:
        db.add_all(
            [
                models.OutbreakSnapshot(
                    source="who_covid_cases",
                    source_id="who_covid_cases:ca:latest",
                    condition_name="COVID-19",
                    country="Canada",
                    region_type="country",
                    metric_name="new_cases",
                    metric_value=1500.0,
                    report_date=latest,
                ),
                models.OutbreakSnapshot(
                    source="who_covid_cases",
                    source_id="who_covid_cases:de:prior",
                    condition_name="COVID-19",
                    country="Germany",
                    region_type="country",
                    metric_name="new_cases",
                    metric_value=1200.0,
                    report_date=prior,
                ),
            ]
        )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks/aggregate")
    assert response.status_code == 200
    data = response.json()
    covid = data["diseases"]["COVID-19"]
    assert covid["global"]["weekly_new"] == 1500
    assert covid["global"]["weekly_change"] == 300
    assert covid["global"]["ytd"] == 2700


def test_outbreaks_aggregate_global_ecdc_includes_us(client):
    """Europe-only sources (ECDC) are combined with US totals so global is not zero.

    US hospital admissions are used as the accounting basis when no case-count
    feed exists, and the global block uses the European data.
    """
    from datetime import datetime, timedelta
    from app.database import SessionLocal
    from app import models

    latest = datetime.utcnow() - timedelta(days=1)
    db = SessionLocal()
    try:
        db.add_all(
            [
                models.OutbreakSnapshot(
                    source="cdc_hosp_resp",
                    source_id="cdc_hosp_resp:us:rsv:40",
                    condition_name="Respiratory Syncytial Virus",
                    country="United States",
                    region="U.S. Residents",
                    region_type="country",
                    metric_name="new_admissions",
                    metric_value=120.0,
                    report_date=latest,
                ),
                models.OutbreakSnapshot(
                    source="ecdc_respiratory",
                    source_id="ecdc_respiratory:deu:rsv:202640",
                    condition_name="Respiratory Syncytial Virus",
                    country="Germany",
                    region_type="country",
                    metric_name="rate",
                    metric_value=45.0,
                    report_date=latest,
                ),
                models.OutbreakSnapshot(
                    source="ecdc_respiratory",
                    source_id="ecdc_respiratory:deu:rsv:202639",
                    condition_name="Respiratory Syncytial Virus",
                    country="Germany",
                    region_type="country",
                    metric_name="rate",
                    metric_value=40.0,
                    report_date=latest - timedelta(days=7),
                ),
            ]
        )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks/aggregate")
    assert response.status_code == 200
    data = response.json()
    rsv = data["diseases"]["Respiratory Syncytial Virus"]
    assert rsv["us"]["weekly_new"] == 120
    assert rsv["us"]["is_admissions"] is True
    # Global count comes from ECDC only; US admissions are not added on top.
    assert rsv["global"]["weekly_new"] == 45
    assert "ecdc_respiratory" in rsv["global"]["source"]


def test_outbreaks_aggregate_global_who_don_alerts_not_case_counts(client):
    """WHO DON alerts are event notifications, not cumulative case counts."""
    from datetime import datetime, timedelta
    from app.database import SessionLocal
    from app import models

    latest = datetime.utcnow() - timedelta(days=1)
    db = SessionLocal()
    try:
        db.add_all(
            [
                models.OutbreakSnapshot(
                    source="cdc_measles",
                    source_id="cdc_measles:us:indigenous:40",
                    condition_name="Measles",
                    country="United States",
                    region="U.S. Residents",
                    region_type="country",
                    case_count=4000,
                    weekly_count=200,
                    report_date=latest,
                ),
                models.OutbreakSnapshot(
                    source="who_don",
                    source_id="who_don:measles:deu",
                    condition_name="Measles",
                    country="Germany",
                    region_type="country",
                    metric_value=1.0,
                    report_date=latest,
                ),
            ]
        )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks/aggregate")
    assert response.status_code == 200
    data = response.json()
    measles = data["diseases"]["Measles"]
    assert measles["us"]["ytd"] == 4000
    assert measles["us"]["ytd_label"] == "YTD"
    # WHO DON alerts should not be mixed with case counts; global falls back to US.
    assert measles["global"]["ytd"] == 4000
    assert measles["global"]["ytd_label"] == "YTD"


def test_outbreaks_aggregate_prefers_case_count_over_metric(client):
    """When case-count rows exist, percentage/activity rows are not mixed in."""
    from datetime import datetime, timedelta
    from app.database import SessionLocal
    from app import models

    latest = datetime.utcnow() - timedelta(days=1)
    db = SessionLocal()
    try:
        db.add_all(
            [
                models.OutbreakSnapshot(
                    source="cdc_nndss",
                    source_id="cdc_nndss:flu:us:40",
                    condition_name="Influenza A",
                    country="United States",
                    region="U.S. Residents",
                    region_type="country",
                    metric_name="cases",
                    case_count=1234,
                    weekly_count=50,
                    report_date=latest,
                ),
                models.OutbreakSnapshot(
                    source="cdc_resp_naat",
                    source_id="cdc_resp_naat:flu:us:40",
                    condition_name="Influenza A",
                    country="United States",
                    region="National",
                    region_type="country",
                    metric_name="percent_positivity",
                    metric_value=2.5,
                    report_date=latest,
                ),
            ]
        )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks/aggregate")
    assert response.status_code == 200
    data = response.json()
    flu = data["diseases"]["Influenza A"]
    assert flu["us"]["ytd"] == 1234
    assert flu["us"]["ytd_label"] == "YTD"
    assert flu["us"]["weekly_new"] == 50
    assert flu["us"]["sources"] == ["cdc_nndss"]


def test_outbreaks_aggregate_admissions_used_when_no_cases(client):
    """Hospital-admission metrics fill the stats when no case-count feed exists."""
    from datetime import datetime, timedelta
    from app.database import SessionLocal
    from app import models

    latest = datetime.utcnow() - timedelta(days=1)
    db = SessionLocal()
    try:
        db.add_all(
            [
                models.OutbreakSnapshot(
                    source="cdc_hosp_resp",
                    source_id="cdc_hosp_resp:us:covid:40",
                    condition_name="COVID-19",
                    country="United States",
                    region="U.S. Residents",
                    region_type="country",
                    metric_name="new_admissions",
                    metric_value=4100.0,
                    report_date=latest,
                ),
            ]
        )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks/aggregate")
    assert response.status_code == 200
    data = response.json()
    covid = data["diseases"]["COVID-19"]
    assert covid["us"]["weekly_new"] == 4100
    assert covid["us"]["ytd"] == 4100
    # With only one weekly snapshot, change equals the weekly value.
    assert covid["us"]["weekly_change"] == 4100
    assert covid["us"]["is_admissions"] is True
    assert covid["us"]["source"] == "cdc_hosp_resp"


def test_outbreaks_aggregate_prefers_admissions_over_wastewater(client):
    """When both admissions and wastewater exist, admissions drive the card."""
    from datetime import datetime, timedelta
    from app.database import SessionLocal
    from app import models

    latest = datetime.utcnow() - timedelta(days=1)
    db = SessionLocal()
    try:
        db.add_all(
            [
                models.OutbreakSnapshot(
                    source="cdc_hosp_resp",
                    source_id="cdc_hosp_resp:us:covid:40",
                    condition_name="COVID-19",
                    country="United States",
                    region="U.S. Residents",
                    region_type="country",
                    metric_name="new_admissions",
                    metric_value=5000.0,
                    report_date=latest,
                ),
                models.OutbreakSnapshot(
                    source="cdc_wastewater",
                    source_id="cdc_wastewater:us:covid:40",
                    condition_name="COVID-19",
                    country="United States",
                    region="California",
                    region_type="state",
                    metric_name="wastewater_level",
                    metric_value=12.5,
                    report_date=latest,
                ),
            ]
        )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks/aggregate")
    assert response.status_code == 200
    data = response.json()
    covid = data["diseases"]["COVID-19"]
    assert covid["us"]["weekly_new"] == 5000
    assert covid["us"]["ytd"] == 5000
    assert covid["us"]["is_admissions"] is True
    assert covid["us"]["source"] == "cdc_hosp_resp"


def test_outbreaks_aggregate_us_admissions_ytd(client):
    """US hospital-admission feeds report YTD by summing weekly admissions."""
    from datetime import datetime, timedelta
    from app.database import SessionLocal
    from app import models

    latest = datetime.utcnow() - timedelta(days=1)
    prior = datetime.utcnow() - timedelta(days=8)
    db = SessionLocal()
    try:
        db.add_all(
            [
                models.OutbreakSnapshot(
                    source="cdc_hosp_resp",
                    source_id="cdc_hosp_resp:us:covid:41",
                    condition_name="COVID-19",
                    country="United States",
                    region="U.S. Residents",
                    region_type="country",
                    metric_name="new_admissions",
                    metric_value=4001.0,
                    report_date=latest,
                ),
                models.OutbreakSnapshot(
                    source="cdc_hosp_resp",
                    source_id="cdc_hosp_resp:us:covid:40",
                    condition_name="COVID-19",
                    country="United States",
                    region="U.S. Residents",
                    region_type="country",
                    metric_name="new_admissions",
                    metric_value=4253.0,
                    report_date=prior,
                ),
            ]
        )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks/aggregate")
    assert response.status_code == 200
    data = response.json()
    covid = data["diseases"]["COVID-19"]
    assert covid["us"]["weekly_new"] == 4001
    assert covid["us"]["ytd"] == 8254
    assert covid["us"]["weekly_change"] == -252
    assert covid["us"]["is_admissions"] is True
    assert covid["us"]["source"] == "cdc_hosp_resp"


def test_outbreaks_aggregate_percentage_returns_null_counts(client):
    """Percentage-only metrics do not surface as case counts."""
    from datetime import datetime, timedelta
    from app.database import SessionLocal
    from app import models

    latest = datetime.utcnow() - timedelta(days=1)
    db = SessionLocal()
    try:
        db.add_all(
            [
                models.OutbreakSnapshot(
                    source="cdc_resp_naat",
                    source_id="cdc_resp_naat:us:flu:40",
                    condition_name="Influenza A",
                    country="United States",
                    region="National",
                    region_type="country",
                    metric_name="percent_positivity",
                    metric_value=3.5,
                    report_date=latest,
                ),
            ]
        )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks/aggregate")
    assert response.status_code == 200
    data = response.json()
    flu = data["diseases"]["Influenza A"]
    assert flu["us"]["weekly_new"] is None
    assert flu["us"]["ytd"] is None
    assert flu["us"]["weekly_change"] is None
    assert flu["us"]["source"] == "cdc_resp_naat"


def test_outbreaks_aggregate_global_covid_includes_asia(client):
    """WHO COVID-19 global coverage includes Asian/Southeast-Asian countries."""
    from datetime import datetime, timedelta
    from app.database import SessionLocal
    from app import models

    db = SessionLocal()
    latest = datetime.utcnow() - timedelta(days=1)
    prior = datetime.utcnow() - timedelta(days=8)
    try:
        for country in ["China", "India", "Viet Nam", "United States"]:
            db.add(
                models.OutbreakSnapshot(
                    source="who_covid_cases",
                    source_id=f"who_covid_cases:{country.lower()}:latest",
                    condition_name="COVID-19",
                    country=country,
                    region_type="country",
                    metric_name="new_cases",
                    metric_value=300.0,
                    report_date=latest,
                )
            )
            db.add(
                models.OutbreakSnapshot(
                    source="who_covid_cases",
                    source_id=f"who_covid_cases:{country.lower()}:prior",
                    condition_name="COVID-19",
                    country=country,
                    region_type="country",
                    metric_name="new_cases",
                    metric_value=250.0,
                    report_date=prior,
                )
            )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks/aggregate")
    assert response.status_code == 200
    data = response.json()
    covid = data["diseases"]["COVID-19"]
    # 4 countries * 300 = 1200 (latest meaningful weekly snapshot)
    assert covid["global"]["weekly_new"] == 1200
    assert covid["global"]["weekly_change"] == 200
    assert covid["global"]["sources"] == ["who_covid_cases"]


def test_outbreaks_aggregate_merges_canonical_synonyms(client):
    """Stale rows with non-canonical condition names must merge into the
    representative bucket, not create empty duplicate entries."""
    from datetime import datetime, timedelta
    from app.database import SessionLocal
    from app import models

    latest = datetime.utcnow() - timedelta(days=1)
    db = SessionLocal()
    try:
        db.add_all(
            [
                models.OutbreakSnapshot(
                    source="cdc_hosp_resp",
                    source_id="rsv:stale",
                    condition_name="RSV",
                    country="United States",
                    region="U.S. Residents",
                    region_type="country",
                    metric_name="new_admissions",
                    metric_value=605.0,
                    report_date=latest,
                ),
                models.OutbreakSnapshot(
                    source="who_covid_cases",
                    source_id="covid:stale",
                    condition_name="SARS-CoV-2",
                    country="China",
                    region_type="country",
                    metric_name="new_cases",
                    metric_value=100.0,
                    report_date=latest,
                ),
            ]
        )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks/aggregate")
    assert response.status_code == 200
    data = response.json()["diseases"]
    assert "RSV" not in data
    assert "SARS-CoV-2" not in data
    # Admissions are used when no case-count feed exists.
    assert data["Respiratory Syncytial Virus"]["us"]["weekly_new"] == 605
    assert data["Respiratory Syncytial Virus"]["us"]["is_admissions"] is True
    assert data["Respiratory Syncytial Virus"]["us"]["source"] == "cdc_hosp_resp"
    assert data["COVID-19"]["global"]["weekly_new"] >= 100


def test_outbreaks_aggregate_global_who_flunet_influenza(client):
    """WHO FluNet provides global Influenza A totals without double-counting US."""
    from datetime import datetime, timedelta
    from app.database import SessionLocal
    from app import models

    latest = datetime.utcnow() - timedelta(days=1)
    prior = datetime.utcnow() - timedelta(days=8)
    db = SessionLocal()
    try:
        db.add_all(
            [
                # US CDC admissions should drive the US card.
                models.OutbreakSnapshot(
                    source="cdc_hosp_resp",
                    source_id="cdc:us:flu:42",
                    condition_name="Influenza A",
                    country="United States",
                    region="U.S. Residents",
                    region_type="country",
                    metric_name="new_admissions",
                    metric_value=1000.0,
                    report_date=latest,
                ),
                # WHO FluNet covers all countries including US.
                models.OutbreakSnapshot(
                    source="who_flunet",
                    source_id="flunet:usa:202642:INF_A",
                    condition_name="Influenza A",
                    country="United States of America",
                    region_type="country",
                    metric_name="cases",
                    metric_value=700.0,
                    case_count=700,
                    report_date=latest,
                ),
                models.OutbreakSnapshot(
                    source="who_flunet",
                    source_id="flunet:deu:202642:INF_A",
                    condition_name="Influenza A",
                    country="Germany",
                    region_type="country",
                    metric_name="cases",
                    metric_value=400.0,
                    case_count=400,
                    report_date=latest,
                ),
                models.OutbreakSnapshot(
                    source="who_flunet",
                    source_id="flunet:deu:202641:INF_A",
                    condition_name="Influenza A",
                    country="Germany",
                    region_type="country",
                    metric_name="cases",
                    metric_value=300.0,
                    case_count=300,
                    report_date=prior,
                ),
            ]
        )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks/aggregate")
    assert response.status_code == 200
    data = response.json()
    flu = data["diseases"]["Influenza A"]
    # US hospital admissions drive the US card when no case-count feed exists.
    assert flu["us"]["weekly_new"] == 1000
    assert flu["us"]["is_admissions"] is True
    assert flu["us"]["source"] == "cdc_hosp_resp"
    # Global should use WHO FluNet only (coverage global), not add CDC US admissions.
    assert flu["global"]["weekly_new"] == 1100
    assert flu["global"]["ytd"] == 1400
    assert flu["global"]["source"] == "who_flunet"


def test_outbreaks_aggregate_global_who_flunet_rsv(client):
    """WHO FluNet provides global RSV totals."""
    from datetime import datetime, timedelta
    from app.database import SessionLocal
    from app import models

    latest = datetime.utcnow() - timedelta(days=1)
    db = SessionLocal()
    try:
        db.add_all(
            [
                models.OutbreakSnapshot(
                    source="who_flunet",
                    source_id="flunet:usa:202642:RSV",
                    condition_name="Respiratory Syncytial Virus",
                    country="United States of America",
                    region_type="country",
                    metric_name="cases",
                    metric_value=150.0,
                    case_count=150,
                    report_date=latest,
                ),
                models.OutbreakSnapshot(
                    source="who_flunet",
                    source_id="flunet:deu:202642:RSV",
                    condition_name="Respiratory Syncytial Virus",
                    country="Germany",
                    region_type="country",
                    metric_name="cases",
                    metric_value=80.0,
                    case_count=80,
                    report_date=latest,
                ),
            ]
        )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks/aggregate")
    assert response.status_code == 200
    data = response.json()
    rsv = data["diseases"]["Respiratory Syncytial Virus"]
    assert rsv["global"]["weekly_new"] == 230
    assert rsv["global"]["ytd"] == 230
    assert rsv["global"]["source"] == "who_flunet"
    assert rsv["global"]["coverage"] == "global"


def test_outbreaks_aggregate_global_who_flunet_ari(client):
    """WHO FluNet ILI activity proxies global ARI activity level."""
    from datetime import datetime, timedelta
    from app.database import SessionLocal
    from app import models

    latest = datetime.utcnow() - timedelta(days=1)
    prior = datetime.utcnow() - timedelta(days=8)
    db = SessionLocal()
    try:
        db.add_all(
            [
                models.OutbreakSnapshot(
                    source="who_flunet",
                    source_id="flunet:usa:202642:ILI",
                    condition_name="Acute Respiratory Infection",
                    country="United States of America",
                    region_type="country",
                    metric_name="ili_activity",
                    metric_value=3.0,
                    report_date=latest,
                ),
                models.OutbreakSnapshot(
                    source="who_flunet",
                    source_id="flunet:deu:202642:ILI",
                    condition_name="Acute Respiratory Infection",
                    country="Germany",
                    region_type="country",
                    metric_name="ili_activity",
                    metric_value=2.0,
                    report_date=latest,
                ),
                models.OutbreakSnapshot(
                    source="who_flunet",
                    source_id="flunet:deu:202641:ILI",
                    condition_name="Acute Respiratory Infection",
                    country="Germany",
                    region_type="country",
                    metric_name="ili_activity",
                    metric_value=1.0,
                    report_date=prior,
                ),
            ]
        )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks/aggregate")
    assert response.status_code == 200
    data = response.json()
    ari = data["diseases"]["Acute Respiratory Infection"]
    # ILI activity is not surfaced as a case count.
    assert ari["global"]["weekly_new"] is None
    assert ari["global"]["ytd"] is None
    assert ari["global"]["source"] == "who_flunet"


def test_outbreaks_aggregate_global_who_flunet_skips_incomplete_week(client):
    """The absolute latest week is ignored when it has far fewer reporters."""
    from datetime import datetime, timedelta
    from app.database import SessionLocal
    from app import models

    latest = datetime.utcnow() - timedelta(days=1)
    complete = datetime.utcnow() - timedelta(days=8)
    db = SessionLocal()
    try:
        # Latest week: only one country reported.
        db.add(
            models.OutbreakSnapshot(
                source="who_flunet",
                source_id="flunet:aus:202643:INF_A",
                condition_name="Influenza A",
                country="Australia",
                region_type="country",
                metric_name="cases",
                metric_value=2.0,
                case_count=2,
                report_date=latest,
            )
        )
        # Prior week: many countries reported.
        for country in ["Germany", "France", "Italy", "Spain", "Japan"]:
            db.add(
                models.OutbreakSnapshot(
                    source="who_flunet",
                    source_id=f"flunet:{country.lower()}:202642:INF_A",
                    condition_name="Influenza A",
                    country=country,
                    region_type="country",
                    metric_name="cases",
                    metric_value=100.0,
                    case_count=100,
                    report_date=complete,
                )
            )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks/aggregate")
    assert response.status_code == 200
    data = response.json()
    flu = data["diseases"]["Influenza A"]
    assert flu["global"]["weekly_new"] == 500
    assert flu["global"]["report_date"].startswith(complete.strftime("%Y-%m-%d"))


def test_outbreaks_aggregate_global_who_measles(client):
    """WHO monthly measles feed provides a global case total."""
    from datetime import datetime, timedelta
    from app.database import SessionLocal
    from app import models

    latest = datetime.utcnow() - timedelta(days=1)
    prior_month = datetime.utcnow() - timedelta(days=35)
    db = SessionLocal()
    try:
        db.add_all(
            [
                models.OutbreakSnapshot(
                    source="who_measles_monthly",
                    source_id="measles:nga:2026:09",
                    condition_name="Measles",
                    country="Nigeria",
                    region_type="country",
                    metric_name="cases",
                    metric_value=100.0,
                    case_count=100,
                    report_date=latest,
                ),
                models.OutbreakSnapshot(
                    source="who_measles_monthly",
                    source_id="measles:deu:2026:09",
                    condition_name="Measles",
                    country="Germany",
                    region_type="country",
                    metric_name="cases",
                    metric_value=50.0,
                    case_count=50,
                    report_date=latest,
                ),
                models.OutbreakSnapshot(
                    source="who_measles_monthly",
                    source_id="measles:deu:2026:08",
                    condition_name="Measles",
                    country="Germany",
                    region_type="country",
                    metric_name="cases",
                    metric_value=30.0,
                    case_count=30,
                    report_date=prior_month,
                ),
            ]
        )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks/aggregate")
    assert response.status_code == 200
    data = response.json()
    measles = data["diseases"]["Measles"]
    assert measles["global"]["weekly_new"] == 150
    assert measles["global"]["ytd"] == 180
    assert measles["global"]["source"] == "who_measles_monthly"
    assert measles["global"]["coverage"] == "global"


def test_outbreaks_aggregate_global_who_measles_skips_incomplete_month(client):
    """The absolute latest month is ignored when it has far fewer reporters."""
    from datetime import datetime, timedelta
    from app.database import SessionLocal
    from app import models

    incomplete = datetime.utcnow() - timedelta(days=1)
    complete = datetime.utcnow() - timedelta(days=35)
    db = SessionLocal()
    try:
        # Incomplete latest month: only one country.
        db.add(
            models.OutbreakSnapshot(
                source="who_measles_monthly",
                source_id="measles:aus:2026:10",
                condition_name="Measles",
                country="Australia",
                region_type="country",
                metric_name="cases",
                metric_value=11.0,
                case_count=11,
                report_date=incomplete,
            )
        )
        # Complete prior month: many countries.
        for country in ["Nigeria", "Germany", "India", "Brazil", "Indonesia"]:
            db.add(
                models.OutbreakSnapshot(
                    source="who_measles_monthly",
                    source_id=f"measles:{country.lower()}:2026:09",
                    condition_name="Measles",
                    country=country,
                    region_type="country",
                    metric_name="cases",
                    metric_value=100.0,
                    case_count=100,
                    report_date=complete,
                )
            )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks/aggregate")
    assert response.status_code == 200
    data = response.json()
    measles = data["diseases"]["Measles"]
    assert measles["global"]["weekly_new"] == 500
    assert measles["global"]["report_date"].startswith(complete.strftime("%Y-%m-%d"))


def test_outbreaks_aggregate_global_who_mpox(client):
    """WHO Mpox feed provides the latest meaningful weekly global snapshot."""
    from datetime import datetime, timedelta
    from app.database import SessionLocal
    from app import models

    db = SessionLocal()
    latest = datetime.utcnow() - timedelta(days=1)
    prior = datetime.utcnow() - timedelta(days=8)
    try:
        db.add_all(
            [
                models.OutbreakSnapshot(
                    source="who_mpox",
                    source_id="mpox:usa:latest",
                    condition_name="Mpox",
                    country="United States of America",
                    region_type="country",
                    metric_name="new_cases",
                    metric_value=50.0,
                    case_count=50,
                    report_date=latest,
                ),
                models.OutbreakSnapshot(
                    source="who_mpox",
                    source_id="mpox:deu:prior",
                    condition_name="Mpox",
                    country="Germany",
                    region_type="country",
                    metric_name="new_cases",
                    metric_value=40.0,
                    case_count=40,
                    report_date=prior,
                ),
            ]
        )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks/aggregate")
    assert response.status_code == 200
    data = response.json()
    mpox = data["diseases"]["Mpox"]
    assert mpox["global"]["weekly_new"] == 50
    assert mpox["global"]["weekly_change"] == 10
    assert mpox["global"]["ytd"] == 90
    assert mpox["global"]["source"] == "who_mpox"
    assert mpox["global"]["coverage"] == "global"


def test_outbreaks_aggregate_paho_dengue_combines_with_us(client):
    """Americas-only PAHO dengue data is combined with US CDC dengue data."""
    from datetime import datetime, timedelta
    from app.database import SessionLocal
    from app import models

    latest = datetime.utcnow() - timedelta(days=1)
    db = SessionLocal()
    try:
        db.add_all(
            [
                models.OutbreakSnapshot(
                    source="cdc_dengue",
                    source_id="cdc:us:fl:42",
                    condition_name="Dengue fever",
                    country="United States",
                    region="Florida",
                    region_type="state",
                    metric_name="cases",
                    metric_value=20.0,
                    case_count=20,
                    weekly_count=20,
                    report_date=latest,
                ),
                models.OutbreakSnapshot(
                    source="paho_dengue",
                    source_id="paho:bra:202642",
                    condition_name="Dengue fever",
                    country="Brazil",
                    region_type="country",
                    metric_name="cases",
                    metric_value=500.0,
                    case_count=500,
                    report_date=latest,
                ),
            ]
        )
        db.commit()
    finally:
        db.close()

    response = client.get("/outbreaks/aggregate")
    assert response.status_code == 200
    data = response.json()
    dengue = data["diseases"]["Dengue fever"]
    assert dengue["us"]["ytd"] == 20
    assert dengue["us"]["weekly_new"] == 20
    assert dengue["global"]["weekly_new"] == 520
    assert dengue["global"]["source"] == "cdc_dengue, paho_dengue"
