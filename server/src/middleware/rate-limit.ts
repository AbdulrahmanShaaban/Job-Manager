import { rateLimit } from "express-rate-limit";
import type { RequestHandler } from "express";
import { env } from "../config/env.ts";

function limiter(options: { windowMs: number; limit: number; message: string }): RequestHandler {
  if (env.NODE_ENV === "test") {
    return (_req, _res, next) => next();
  }
  return rateLimit({
    windowMs: options.windowMs,
    limit: options.limit,
    standardHeaders: "draft-8",
    legacyHeaders: false,
    message: {
      error: {
        code: "RATE_LIMITED",
        message: options.message,
      },
    },
  });
}

export const globalRateLimit = limiter({
  windowMs: 15 * 60 * 1000,
  limit: 300,
  message: "Too many requests. Please slow down and try again shortly.",
});

export const authRateLimit = limiter({
  windowMs: 15 * 60 * 1000,
  limit: 15,
  message: "Too many sign-in attempts. Try again in a few minutes.",
});

export const voiceRateLimit = limiter({
  windowMs: 60 * 60 * 1000,
  limit: 60,
  message: "Voice limit reached for now. You can keep working manually.",
});

export const writeRateLimit = limiter({
  windowMs: 15 * 60 * 1000,
  limit: 180,
  message: "Too many changes at once. Please wait a moment.",
});
