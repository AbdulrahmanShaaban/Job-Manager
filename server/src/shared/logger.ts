import { env } from "../config/env.ts";

const REDACTED_KEYS = new Set([
  "authorization",
  "password",
  "passwordhash",
  "token",
  "access_token",
  "refreshtoken",
  "apikey",
  "api_key",
  "gemini_api_key",
  "groq_api_key",
]);

function redact(value: unknown, depth = 0): unknown {
  if (depth > 4) return "[deep]";
  if (Array.isArray(value)) return value.map((item) => redact(item, depth + 1));
  if (value && typeof value === "object") {
    const output: Record<string, unknown> = {};
    for (const [key, entry] of Object.entries(value as Record<string, unknown>)) {
      output[key] = REDACTED_KEYS.has(key.toLowerCase()) ? "[redacted]" : redact(entry, depth + 1);
    }
    return output;
  }
  return value;
}

type Level = "info" | "warn" | "error";

function write(level: Level, message: string, meta?: Record<string, unknown>): void {
  if (env.NODE_ENV === "test") return;
  const line = {
    level,
    time: new Date().toISOString(),
    message,
    ...(meta ? { meta: redact(meta) } : {}),
  };
  const serialized = JSON.stringify(line);
  if (level === "error") {
    console.error(serialized);
  } else {
    console.log(serialized);
  }
}

export const logger = {
  info: (message: string, meta?: Record<string, unknown>) => write("info", message, meta),
  warn: (message: string, meta?: Record<string, unknown>) => write("warn", message, meta),
  error: (message: string, meta?: Record<string, unknown>) => write("error", message, meta),
};
