"""
Minimal FastAPI "agent" service.

This is deliberately small: it is the *workload* the golden-path platform
deploys. The platform around it (Terraform, CI/CD, policy gates, GitOps,
observability) is the real deliverable.

Endpoints:
  GET  /         service info and endpoint list
  GET  /health   liveness probe (is the process up?)
  GET  /ready    readiness probe (should this pod receive traffic?)
  POST /agent    stubbed "agentic" call that mimics a Bedrock-backed LLM step
  GET  /metrics  Prometheus exposition

Runtime knobs (environment variables, read on every request so they can be
changed with `kubectl set env` without rebuilding the image):
  APP_VERSION       version label, injected at build time
  MOCK_LLM          "true" = fake model call, no cloud needed (default)
  FAILURE_RATE      0.0-1.0, fraction of /agent calls that return HTTP 500
  EXTRA_LATENCY_MS  extra delay added to every /agent call

FAILURE_RATE and EXTRA_LATENCY_MS exist for chaos drills: they let you burn
the error budget or the latency SLO on purpose and watch the alerts fire.
"""

import json
import os
import random
import socket
import sys
import time

from fastapi import FastAPI, HTTPException, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest
from pydantic import BaseModel

APP_VERSION = os.getenv("APP_VERSION", "dev")
POD_NAME = socket.gethostname()

# Known routes. Anything else is labelled "other" so a scanner hitting random
# URLs can't explode metric cardinality.
KNOWN_PATHS = {"/", "/health", "/ready", "/agent", "/metrics"}
QUIET_PATHS = {"/health", "/ready", "/metrics"}  # probes/scrapes: not logged

app = FastAPI(title="agentic-golden-path demo", version=APP_VERSION)

REQUESTS = Counter("agent_requests_total", "Total HTTP requests", ["endpoint", "status"])
LATENCY = Histogram(
    "agent_request_latency_seconds",
    "Request latency",
    ["endpoint"],
    buckets=(0.05, 0.1, 0.25, 0.5, 0.75, 1.0, 1.5, 2.5, 5.0),
)
# Constant 1, labelled with the running version: shows in Grafana which
# version each pod serves while a rolling update is in progress.
BUILD_INFO = Gauge("agent_build_info", "Build information", ["version"])
BUILD_INFO.labels(APP_VERSION).set(1)


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, default))
    except ValueError:
        return default


@app.middleware("http")
async def observe(request: Request, call_next):
    """Count, time and log every request in one place."""
    endpoint = request.url.path if request.url.path in KNOWN_PATHS else "other"
    start = time.perf_counter()
    status = 500
    try:
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        elapsed = time.perf_counter() - start
        REQUESTS.labels(endpoint, str(status)).inc()
        if endpoint != "/metrics":
            LATENCY.labels(endpoint).observe(elapsed)
        if endpoint not in QUIET_PATHS:
            # One JSON object per line on stdout: the platform (Promtail ->
            # Loki) collects it; the app never manages log files.
            print(
                json.dumps(
                    {
                        "ts": round(time.time(), 3),
                        "level": "error" if status >= 500 else "info",
                        "method": request.method,
                        "path": request.url.path,
                        "status": status,
                        "latency_ms": round(elapsed * 1000, 1),
                        "pod": POD_NAME,
                        "version": APP_VERSION,
                    }
                ),
                file=sys.stdout,
                flush=True,
            )


class AgentRequest(BaseModel):
    prompt: str


class AgentResponse(BaseModel):
    reply: str
    model: str
    latency_ms: float


@app.get("/")
def root():
    return {
        "service": "agentic-golden-path",
        "version": APP_VERSION,
        "pod": POD_NAME,
        "endpoints": ["/health", "/ready", "POST /agent", "/metrics", "/docs"],
    }


@app.get("/health")
def health():
    return {"status": "ok", "version": APP_VERSION}


@app.get("/ready")
def ready():
    # Placeholder for real dependency checks (Postgres, Redis, Bedrock).
    return {"status": "ready"}


@app.post("/agent", response_model=AgentResponse)
def agent(req: AgentRequest):
    start = time.perf_counter()

    extra_ms = _env_float("EXTRA_LATENCY_MS", 0.0)
    if extra_ms > 0:
        time.sleep(extra_ms / 1000)

    if random.random() < _env_float("FAILURE_RATE", 0.0):
        raise HTTPException(status_code=500, detail="injected failure (FAILURE_RATE)")

    if os.getenv("MOCK_LLM", "true").lower() == "true":
        # Simulated model latency gives the dashboards something to show.
        time.sleep(random.uniform(0.05, 0.25))
        reply = f"[mock] processed {len(req.prompt)} chars of procurement text"
        model = "mock-bedrock-claude"
    else:  # pragma: no cover - real path not exercised in CI
        raise HTTPException(status_code=501, detail="Bedrock call not wired up yet")

    elapsed_ms = (time.perf_counter() - start) * 1000
    return AgentResponse(reply=reply, model=model, latency_ms=round(elapsed_ms, 2))


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
