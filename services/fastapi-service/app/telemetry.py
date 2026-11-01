"""OpenTelemetry setup for the order service.

Signals go out over OTLP/HTTP. Endpoint, protocol, and propagators come from
the standard OTEL_* environment variables. The collector is the only backend
this process knows about.
"""

from __future__ import annotations

import logging
import os

from opentelemetry import metrics, trace
from opentelemetry._logs import set_logger_provider
from opentelemetry.baggage.propagation import W3CBaggagePropagator
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.instrumentation.logging.handler import LoggingHandler
from opentelemetry.propagate import set_global_textmap
from opentelemetry.propagators.composite import CompositePropagator
from opentelemetry.sdk._logs import LoggerProvider
from opentelemetry.sdk._logs.export import (
    BatchLogRecordProcessor,
    SimpleLogRecordProcessor,
)
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor, SimpleSpanProcessor
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

logger = logging.getLogger(__name__)

# Probe and schema routes stay out of traces. Comma-separated regexes, matched
# with re.search against the request URL.
_EXCLUDED_URLS = "/health$,/ready$,/metrics$,/docs,/redoc,/openapi\\.json"

_configured = False
_tracer_provider: TracerProvider | None = None
_meter_provider: MeterProvider | None = None
_logger_provider: LoggerProvider | None = None


def _sdk_disabled() -> bool:
    return os.getenv("OTEL_SDK_DISABLED", "").strip().lower() in {"1", "true", "yes"}


def _resource(
    service_name: str, service_version: str, service_namespace: str
) -> Resource:
    attributes: dict[str, str] = {
        "service.name": service_name,
        "service.version": service_version,
    }
    resource_env = os.getenv("OTEL_RESOURCE_ATTRIBUTES", "")
    if "service.namespace=" not in resource_env:
        attributes["service.namespace"] = service_namespace
    if "deployment.environment.name=" not in resource_env:
        attributes["deployment.environment.name"] = os.getenv(
            "DEPLOYMENT_ENVIRONMENT", "local"
        )
    # Resource.create also folds in OTEL_RESOURCE_ATTRIBUTES.
    return Resource.create(attributes)


def configure_telemetry(
    app,
    *,
    service_namespace: str,
    service_name: str,
    service_version: str,
    span_exporter=None,
    metric_reader=None,
    log_exporter=None,
) -> None:
    """Install providers and FastAPI instrumentation. Safe to call once per process."""
    global _configured, _tracer_provider, _meter_provider, _logger_provider
    if _configured:
        return

    set_global_textmap(
        CompositePropagator(
            [
                TraceContextTextMapPropagator(),
                W3CBaggagePropagator(),
            ]
        )
    )

    resource = _resource(service_name, service_version, service_namespace)
    testing = span_exporter is not None

    tracer_provider = TracerProvider(resource=resource)
    if testing:
        tracer_provider.add_span_processor(SimpleSpanProcessor(span_exporter))
    else:
        tracer_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    trace.set_tracer_provider(tracer_provider)
    _tracer_provider = tracer_provider

    if metric_reader is None and not testing:
        metric_reader = PeriodicExportingMetricReader(OTLPMetricExporter())
    meter_provider = None
    if metric_reader is not None:
        meter_provider = MeterProvider(
            resource=resource, metric_readers=[metric_reader]
        )
        metrics.set_meter_provider(meter_provider)
        _meter_provider = meter_provider

    if log_exporter is None and not testing:
        log_exporter = OTLPLogExporter()
    if log_exporter is not None:
        logger_provider = LoggerProvider(resource=resource)
        processor = (
            SimpleLogRecordProcessor(log_exporter)
            if testing
            else BatchLogRecordProcessor(log_exporter)
        )
        logger_provider.add_log_record_processor(processor)
        set_logger_provider(logger_provider)
        # The logging instrumentor attaches its own OTLP handler. Adding a
        # second handler would export every record twice.
        LoggingInstrumentor().instrument(
            set_logging_format=False,
            inject_trace_context=True,
        )
        _logger_provider = logger_provider

    FastAPIInstrumentor.instrument_app(
        app,
        tracer_provider=tracer_provider,
        meter_provider=meter_provider,
        excluded_urls=_EXCLUDED_URLS,
    )
    _configured = True
    logger.info("OpenTelemetry enabled for %s", service_name)


def init_telemetry(
    app,
    *,
    service_namespace: str = "deploy-services",
    service_name: str | None = None,
    service_version: str | None = None,
) -> None:
    if _sdk_disabled():
        logger.info("OpenTelemetry disabled via OTEL_SDK_DISABLED")
        return
    configure_telemetry(
        app,
        service_namespace=service_namespace,
        service_name=service_name or os.getenv("OTEL_SERVICE_NAME", "fastapi-service"),
        service_version=service_version or os.getenv("OTEL_SERVICE_VERSION", "1.0.0"),
    )


def shutdown_telemetry() -> None:
    """Flush exporters. Called from the FastAPI lifespan on the way down."""
    global _tracer_provider, _meter_provider, _logger_provider
    if _logger_provider is not None:
        _logger_provider.force_flush()
    # logging.shutdown() flushes every handler ever created. The OTLP handler
    # flush starts a thread, which fails once the interpreter is tearing down.
    root = logging.getLogger()
    for handler in list(root.handlers):
        if isinstance(handler, LoggingHandler):
            handler.flush = lambda: None  # type: ignore[method-assign]
            root.removeHandler(handler)
            handler.close()
    try:
        LoggingInstrumentor().uninstrument()
    except Exception:
        logger.debug("OpenTelemetry log uninstrument failed", exc_info=True)
    for provider in (_tracer_provider, _meter_provider, _logger_provider):
        if provider is not None:
            provider.shutdown()
    _tracer_provider = None
    _meter_provider = None
    _logger_provider = None
