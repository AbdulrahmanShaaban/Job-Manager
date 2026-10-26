import cors from "cors";
import express from "express";
import helmet from "helmet";
import { env } from "./config/env.ts";
import { ApiError } from "./shared/errors.ts";
import { requestId } from "./middleware/request-id.ts";
import { errorHandler, notFoundHandler } from "./middleware/error-handler.ts";
import { globalRateLimit } from "./middleware/rate-limit.ts";
import { authRouter } from "./modules/auth/routes.ts";
import { workspacesRouter } from "./modules/workspaces/routes.ts";
import { sitesRouter } from "./modules/sites/routes.ts";
import { sitesVisitsRouter } from "./modules/visits/routes.ts";
import { visitsRouter } from "./modules/visits/detail-routes.ts";
import { tasksRouter } from "./modules/tasks/routes.ts";
import { overviewRouter } from "./modules/overview/routes.ts";
import { exportRouter } from "./modules/export/routes.ts";
import { voiceRouter } from "./modules/voice/routes.ts";

export function createApp() {
  const app = express();
  app.disable("x-powered-by");

  if (env.isProduction) app.set("trust proxy", 1);

  app.use(
    helmet({
      crossOriginResourcePolicy: { policy: "cross-origin" },
    }),
  );

  app.use(
    cors({
      origin(origin, callback) {
        if (!origin) {
          // Native mobile clients do not send an Origin header.
          callback(null, true);
          return;
        }
        if (env.corsOrigins.includes(origin)) {
          callback(null, true);
          return;
        }
        callback(new ApiError(403, "FORBIDDEN", "Origin is not allowed"));
      },
      credentials: false,
      maxAge: 600,
      exposedHeaders: ["x-export-truncated", "RateLimit", "RateLimit-Policy"],
    }),
  );

  app.use(requestId);
  // Rate-limit before parsing bodies so oversized/abusive payloads are rejected
  // cheaply. The fallback voice route installs its own raw parser.
  app.use(globalRateLimit);
  app.use((_req, res, next) => {
    // Authenticated API responses must never be cached by proxies or browsers.
    res.setHeader("cache-control", "no-store");
    next();
  });
  app.use(express.json({ limit: "1mb" }));

  app.get("/health", (_req, res) => {
    res.json({ status: "ok", time: new Date().toISOString() });
  });

  app.use("/api/v1/auth", authRouter);
  app.use("/api/v1/workspaces", workspacesRouter);
  app.use("/api/v1/sites", sitesRouter);
  app.use("/api/v1/sites", sitesVisitsRouter);
  app.use("/api/v1/visits", visitsRouter);
  app.use("/api/v1/tasks", tasksRouter);
  app.use("/api/v1/overview", overviewRouter);
  app.use("/api/v1/export", exportRouter);
  app.use("/api/v1/voice", voiceRouter);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
