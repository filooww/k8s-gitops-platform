"""Minimal smoke tests so the CI pipeline has something to run before building."""
from fastapi.testclient import TestClient

from main import app

client = TestClient(app)


def test_root():
    r = client.get("/")
    assert r.status_code == 200
    assert r.json()["service"]


def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_metrics_exposes_prometheus():
    client.get("/health")  # generate at least one sample
    r = client.get("/metrics")
    assert r.status_code == 200
    assert "http_requests_total" in r.text
