import os

# Keep the imported application from opening an OTLP connection during tests.
os.environ["OTEL_SDK_DISABLED"] = "true"
