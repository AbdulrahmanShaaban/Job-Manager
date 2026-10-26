import type { ErrorRequestHandler, RequestHandler } from "express";
import { Prisma } from "../generated/prisma/client.ts";
import { ApiError } from "../shared/errors.ts";
import { logger } from "../shared/logger.ts";
import { env } from "../config/env.ts";
import { z } from "zod";

export const notFoundHandler: RequestHandler = (req, _res, next) => {
  next(new ApiError(404, "NOT_FOUND", `Route not found: ${req.method} ${req.path}`));
};

export const errorHandler: ErrorRequestHandler = (error, req, res, _next) => {
  if (res.headersSent) return;

  if (error instanceof ApiError) {
    res.status(error.status).json({
      error: {
        code: error.code,
        message: error.message,
        ...(error.details !== undefined ? { details: error.details } : {}),
        requestId: req.requestId,
      },
    });
    return;
  }

  if (error instanceof z.ZodError) {
    res.status(422).json({
      error: {
        code: "VALIDATION_ERROR",
        message: "Some fields are invalid",
        details: error.issues.map((issue) => ({
          path: issue.path.join("."),
          message: issue.message,
        })),
        requestId: req.requestId,
      },
    });
    return;
  }

  if (error instanceof Prisma.PrismaClientKnownRequestError) {
    if (error.code === "P2025") {
      res.status(404).json({
        error: { code: "NOT_FOUND", message: "Record not found", requestId: req.requestId },
      });
      return;
    }
    if (error.code === "P2002") {
      res.status(409).json({
        error: {
          code: "CONFLICT",
          message: "A record with these values already exists",
          requestId: req.requestId,
        },
      });
      return;
    }
  }

  if (error instanceof SyntaxError && "body" in error) {
    res.status(400).json({
      error: { code: "BAD_REQUEST", message: "Malformed JSON body", requestId: req.requestId },
    });
    return;
  }

  const maybeHttpError = error as { status?: number; type?: string };
  if (maybeHttpError.status === 413 || maybeHttpError.type === "entity.too.large") {
    res.status(413).json({
      error: {
        code: "PAYLOAD_TOO_LARGE",
        message: "The request is larger than allowed.",
        requestId: req.requestId,
      },
    });
    return;
  }

  logger.error("Unhandled request error", {
    requestId: req.requestId,
    method: req.method,
    path: req.path,
    error: error instanceof Error ? error.message : String(error),
    stack: env.isProduction ? undefined : error instanceof Error ? error.stack : undefined,
  });

  res.status(500).json({
    error: {
      code: "INTERNAL_ERROR",
      message: "Something went wrong. Please try again.",
      requestId: req.requestId,
    },
  });
};
