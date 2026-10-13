import json

import pytest
from fastapi.testclient import TestClient

from main import app

client = TestClient(app)


@pytest.fixture(autouse=True)
def clean_env(monkeypatch):
    # Each test starts with chaos knobs off and the mock LLM on.
    monkeypatch.delenv("FAILURE_RATE", raising=False)
    monkeypatch.delenv("EXTRA_LATENCY_MS", raising=False)
    monkeypatch.setenv("MOCK_LLM", "true")


def test_root_lists_endpoints():
    r = client.get("/")
    assert r.status_code == 200
    assert "POST /agent" in r.json()["endpoints"]


def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_ready():
    r = client.get("/ready")
    assert r.status_code == 200
    assert r.json()["status"] == "ready"


def test_agent_roundtrip():
    r = client.post("/agent", json={"prompt": "negotiate this quote"})
    assert r.status_code == 200
    body = r.json()
    assert body["model"] == "mock-bedrock-claude"
    assert body["latency_ms"] > 0
    assert "processed 20 chars" in body["reply"]


def test_agent_rejects_bad_body():
    r = client.post("/agent", json={"text": "wrong field"})
    assert r.status_code == 422


def test_failure_injection_returns_500_and_is_counted(monkeypatch):
    monkeypatch.setenv("FAILURE_RATE", "1")
    r = client.post("/agent", json={"prompt": "hi"})
    assert r.status_code == 500
    metrics = client.get("/metrics").text
    assert 'agent_requests_total{handler="/agent",status="500"}' in metrics


def test_extra_latency_is_applied(monkeypatch):
    monkeypatch.setenv("EXTRA_LATENCY_MS", "300")
    r = client.post("/agent", json={"prompt": "hi"})
    assert r.status_code == 200
    assert r.json()["latency_ms"] >= 300


def test_unknown_paths_do_not_create_new_labels():
    client.get("/wp-admin")
    metrics = client.get("/metrics").text
    assert 'handler="other"' in metrics
    assert "wp-admin" not in metrics


def test_requests_are_logged_as_json(capsys):
    client.post("/agent", json={"prompt": "hi"})
    lines = [ln for ln in capsys.readouterr().out.splitlines() if ln.startswith("{")]
    entry = json.loads(lines[-1])
    assert entry["path"] == "/agent"
    assert entry["status"] == 200


def test_probes_are_not_logged(capsys):
    client.get("/health")
    assert capsys.readouterr().out == ""


def test_build_info_metric_exposes_version():
    metrics = client.get("/metrics").text
    assert 'agent_build_info{version="' in metrics


# Labels Prometheus (and the Prometheus Operator) attach to every scraped
# series. If the app used one, Prometheus would rename it to exported_<name>
# and every dashboard and alert filtering on it would silently match nothing.
RESERVED_TARGET_LABELS = {"job", "instance", "namespace", "pod", "service", "endpoint", "container"}


def test_metrics_do_not_use_reserved_target_labels():
    client.post("/agent", json={"prompt": "hi"})
    used = set()
    for line in client.get("/metrics").text.splitlines():
        if line.startswith("agent_") and "{" in line:
            labels = line[line.index("{") + 1 : line.index("}")]
            used |= {pair.split("=")[0] for pair in labels.split(",") if "=" in pair}
    assert used, "expected labelled agent_* metrics"
    clash = used & RESERVED_TARGET_LABELS
    assert not clash, f"reserved Prometheus label used: {clash}"
