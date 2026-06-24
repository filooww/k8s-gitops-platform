"""
Demo FastAPI service for the k8s-gitops-platform project.

Exposes:
  GET /            - root, returns service metadata
  GET /health      - liveness/readiness probe target
  GET /work        - simulates CPU work (used to trigger the HPA under load)
  GET /metrics     - Prometheus metrics (request count, latency histogram, in-flight)

All HTTP requests are instrumented via middleware, so every endpoint feeds
the Prometheus histogram that the Grafana dashboard graphs.
"""
import math
import os
import time

from fastapi import FastAPI, Request, Response
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)

APP_VERSION = os.getenv("APP_VERSION", "0.1.0")
APP_NAME = os.getenv("APP_NAME", "k8s-gitops-demo")

app = FastAPI(title=APP_NAME, version=APP_VERSION)

# ---- Prometheus metrics -----------------------------------------------------
REQUESTS = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "path", "status"],
)
LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "path"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5),
)
IN_FLIGHT = Gauge(
    "http_requests_in_flight",
    "Number of HTTP requests currently being served",
)


@app.middleware("http")
async def prometheus_middleware(request: Request, call_next):
    # Use the route template (not the raw path) to keep label cardinality low.
    path = request.scope.get("route").path if request.scope.get("route") else request.url.path
    IN_FLIGHT.inc()
    start = time.perf_counter()
    try:
        response = await call_next(request)
        status = response.status_code
    except Exception:
        status = 500
        raise
    finally:
        IN_FLIGHT.dec()
        elapsed = time.perf_counter() - start
        LATENCY.labels(request.method, path).observe(elapsed)
        REQUESTS.labels(request.method, path, status).inc()
    return response


@app.get("/")
async def root():
    return {
        "service": APP_NAME,
        "version": APP_VERSION,
        "pod": os.getenv("HOSTNAME", "unknown"),
        "message": "GitOps-deployed FastAPI service. See /metrics, /health, /work.",
    }


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/work")
async def work(iterations: int = 200000):
    """Burn some CPU so the HorizontalPodAutoscaler has something to react to."""
    acc = 0.0
    for i in range(1, iterations + 1):
        acc += math.sqrt(i) * math.sin(i)
    return {"iterations": iterations, "result": acc}


@app.get("/metrics")
async def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
