process.env.OTEL_SDK_DISABLED = "true";
process.env.OTEL_SERVICE_NAME = "fastify-service";

import { describe, expect, it } from "vitest";

describe("OpenTelemetry", () => {
  it("starts and shuts down cleanly when the SDK is disabled", async () => {
    const telemetry = await import("../src/telemetry");
    telemetry.initTelemetry();
    await telemetry.shutdownTelemetry();
    expect(process.env.OTEL_SERVICE_NAME).toBe("fastify-service");
    expect(process.env.OTEL_RESOURCE_ATTRIBUTES).toContain(
      "service.namespace=deploy-services",
    );
    expect(process.env.OTEL_RESOURCE_ATTRIBUTES).toContain("service.version=");
  }, 60_000);
});
