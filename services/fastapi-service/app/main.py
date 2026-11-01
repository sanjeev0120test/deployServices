import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from prometheus_fastapi_instrumentator import Instrumentator

from app.routes.health import router as health_router
from app.routes.health import set_ready
from app.routes.orders import router as orders_router
from app.telemetry import init_telemetry, shutdown_telemetry

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(application: FastAPI):
    set_ready(True)
    logger.info("FastAPI service started")
    yield
    set_ready(False)
    shutdown_telemetry()
    logger.info("FastAPI service shutting down")


app = FastAPI(title="FastAPI Order Service", version="1.0.0", lifespan=lifespan)

Instrumentator().instrument(app).expose(app, endpoint="/metrics")

app.include_router(health_router)
app.include_router(orders_router)

init_telemetry(app)


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error("Unhandled exception: %s", exc, exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"error": "Internal Server Error"},
    )
