import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  serverExternalPackages: [
    "prom-client",
    "@opentelemetry/api",
    "@opentelemetry/sdk-node",
    "@opentelemetry/resources",
    "@opentelemetry/instrumentation-http",
  ],
};

export default nextConfig;
