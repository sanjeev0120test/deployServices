import os

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from opentelemetry.sdk._logs.export import InMemoryLogRecordExporter
from opentelemetry.sdk.metrics.export import InMemoryMetricReader
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter

from app.telemetry import configure_telemetry, shutdown_telemetry


@pytest.mark.asyncio
async def test_business_route_is_traced_and_probes_are_not():
    os.environ.pop("OTEL_SDK_DISABLED", None)
    app = FastAPI(title="FastAPI Order Service", version="1.0.0")

    @app.get("/health")
    async def health():
        return {"status": "ok"}

    @app.get("/orders")
    async def orders():
        return {"data": []}

    spans = InMemorySpanExporter()
    configure_telemetry(
        app,
        service_namespace="deploy-services",
        service_name="fastapi-service",
        service_version="1.0.0",
        span_exporter=spans,
        metric_reader=InMemoryMetricReader(),
        log_exporter=InMemoryLogRecordExporter(),
    )

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        health_response = await client.get("/health")
        orders_response = await client.get("/orders")

    assert health_response.status_code == 200
    assert orders_response.status_code == 200

    finished = spans.get_finished_spans()
    described = [f"{span.name} {dict(span.attributes or {})}" for span in finished]
    assert any("orders" in item for item in described), described
    assert all("health" not in item for item in described), described
    assert finished[0].resource.attributes["service.name"] == "fastapi-service"
    assert finished[0].resource.attributes["service.namespace"] == "deploy-services"
    shutdown_telemetry()
