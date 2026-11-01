import { NodeSDK } from "@opentelemetry/sdk-node";
import { HttpInstrumentation } from "@opentelemetry/instrumentation-http";
import {
  defaultResource,
  resourceFromAttributes,
} from "@opentelemetry/resources";

const PROBE_PATHS = new Set([
  "/health",
  "/ready",
  "/metrics",
  "/api/health",
  "/api/ready",
  "/api/metrics",
]);

function isProbe(url: string | undefined): boolean {
  if (!url) {
    return false;
  }
  const path = url.split("?")[0];
  return PROBE_PATHS.has(path);
}

function ensureResourceAttribute(key: string, value: string): void {
  const current = process.env.OTEL_RESOURCE_ATTRIBUTES ?? "";
  const parts = current
    .split(",")
    .map((part) => part.trim())
    .filter((part) => part.length > 0);
  if (parts.some((part) => part.startsWith(`${key}=`))) {
    return;
  }
  parts.push(`${key}=${value}`);
  process.env.OTEL_RESOURCE_ATTRIBUTES = parts.join(",");
}

const serviceName = process.env.OTEL_SERVICE_NAME || "fastify-service";
process.env.OTEL_SERVICE_NAME = serviceName;
const serviceVersion = process.env.OTEL_SERVICE_VERSION || "1.0.0";
process.env.OTEL_SERVICE_VERSION = serviceVersion;
ensureResourceAttribute("service.version", serviceVersion);
ensureResourceAttribute("service.namespace", "deploy-services");
ensureResourceAttribute(
  "deployment.environment.name",
  process.env.DEPLOYMENT_ENVIRONMENT || "local",
);

// Exporters, protocol, and propagators come from OTEL_* so the process does
// not hard-code /v1/traces onto the endpoint.
const sdk = new NodeSDK({
  autoDetectResources: true,
  resource: defaultResource().merge(
    resourceFromAttributes({
      "service.name": serviceName,
      "service.version": serviceVersion,
      "service.namespace": "deploy-services",
      "deployment.environment.name":
        process.env.DEPLOYMENT_ENVIRONMENT || "local",
    }),
  ),
  instrumentations: [
    new HttpInstrumentation({
      ignoreIncomingRequestHook: (request) => isProbe(request.url),
    }),
  ],
});

let started = false;

export function initTelemetry(): void {
  if (started || process.env.OTEL_SDK_DISABLED === "true") {
    return;
  }
  sdk.start();
  started = true;
}

export async function shutdownTelemetry(): Promise<void> {
  if (!started) {
    return;
  }
  started = false;
  await sdk.shutdown();
}
