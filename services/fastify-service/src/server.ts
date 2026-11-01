import { trace } from "@opentelemetry/api";
import { initTelemetry, shutdownTelemetry } from "./telemetry";
initTelemetry();

import Fastify from "fastify";
import cors from "@fastify/cors";
import helmet from "@fastify/helmet";
import metricsPlugin from "./plugins/metrics";
import healthRoutes from "./routes/health";
import itemRoutes from "./routes/items";
import { setReady } from "./routes/health";

const PORT = parseInt(process.env.PORT || "3001", 10);
const HOST = process.env.HOST || "0.0.0.0";

async function main() {
  const fastify = Fastify({
    logger: {
      level: process.env.LOG_LEVEL || "info",
    },
  });

  fastify.setErrorHandler((error: Error & { statusCode?: number }, _request, reply) => {
    fastify.log.error(error);
    const statusCode = error.statusCode ?? 500;
    reply.status(statusCode).send({
      error: statusCode >= 500 ? "Internal Server Error" : error.message,
      statusCode,
    });
  });

  await fastify.register(cors);
  await fastify.register(helmet);
  await fastify.register(metricsPlugin);
  await fastify.register(healthRoutes);
  await fastify.register(itemRoutes);

  fastify.addHook("preHandler", async (request) => {
    const span = trace.getActiveSpan();
    const route = request.routeOptions?.url;
    if (span && route) {
      span.updateName(`${request.method} ${route}`);
      span.setAttribute("http.route", route);
    }
  });

  try {
    await fastify.listen({ port: PORT, host: HOST });
    setReady(true);
    fastify.log.info(`Server listening on ${HOST}:${PORT}`);
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }

  const shutdown = async () => {
    setReady(false);
    fastify.log.info("Shutting down gracefully...");
    await fastify.close();
    await shutdownTelemetry();
    process.exit(0);
  };

  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
}

main();
