import { createApp } from "./app.ts";
import { env } from "./config/env.ts";
import { logger } from "./shared/logger.ts";
import { disconnectPrisma } from "./db/prisma.ts";

const app = createApp();

const server = app.listen(env.PORT, () => {
  logger.info("Job Manager API listening", {
    port: env.PORT,
    environment: env.NODE_ENV,
    ai: {
      gemini: env.ai.geminiConfigured,
      groq: env.ai.groqConfigured,
    },
  });
});

async function shutdown(signal: string): Promise<void> {
  logger.info("Shutting down", { signal });
  server.close(async () => {
    await disconnectPrisma();
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on("SIGINT", () => void shutdown("SIGINT"));
process.on("SIGTERM", () => void shutdown("SIGTERM"));
