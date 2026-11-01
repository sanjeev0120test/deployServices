export async function register(): Promise<void> {
  if (process.env.NEXT_RUNTIME === "edge") {
    return;
  }

  const { NodeSDK } = await import("@opentelemetry/sdk-node");
  const { HttpInstrumentation } = await import(
    "@opentelemetry/instrumentation-http"
  );
  const { defaultResource, resourceFromAttributes } = await import(
    "@opentelemetry/resources"
  );

  const probePaths = new Set([
    "/health",
    "/ready",
    "/metrics",
    "/api/health",
    "/api/ready",
    "/api/metrics",
  ]);

  const serviceName = process.env.OTEL_SERVICE_NAME || "nextjs-service";
  process.env.OTEL_SERVICE_NAME = serviceName;
  const serviceVersion = process.env.OTEL_SERVICE_VERSION || "1.0.0";
  const current = process.env.OTEL_RESOURCE_ATTRIBUTES ?? "";
  const parts = current
    .split(",")
    .map((part) => part.trim())
    .filter((part) => part.length > 0);
  const ensure = (key: string, value: string) => {
    if (!parts.some((part) => part.startsWith(`${key}=`))) {
      parts.push(`${key}=${value}`);
    }
  };
  ensure("service.version", serviceVersion);
  ensure("service.namespace", "deploy-services");
  ensure(
    "deployment.environment.name",
    process.env.DEPLOYMENT_ENVIRONMENT || "local",
  );
  process.env.OTEL_RESOURCE_ATTRIBUTES = parts.join(",");

  if (process.env.OTEL_SDK_DISABLED === "true") {
    return;
  }

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
        ignoreIncomingRequestHook: (request) => {
          const path = (request.url ?? "").split("?")[0];
          return probePaths.has(path);
        },
      }),
    ],
  });

  sdk.start();
  const shutdown = () => {
    sdk.shutdown().catch((error: unknown) => {
      console.error("OpenTelemetry shutdown failed", error);
    });
  };
  process.once("SIGTERM", shutdown);
  process.once("SIGINT", shutdown);
}
