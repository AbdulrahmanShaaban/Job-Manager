import "dotenv/config";
import { z } from "zod";

const boolFromEnv = z
  .enum(["true", "false", "1", "0"])
  .transform((value) => value === "true" || value === "1");

const optionalString = z
  .string()
  .optional()
  .transform((value) => (value && value.trim().length > 0 ? value.trim() : undefined));

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  CORS_ORIGINS: z.string().default(""),
  DATABASE_URL: z.string().optional(),
  AUTH_SECRET: z.string().optional(),
  SESSION_TTL_DAYS: z.coerce.number().int().min(1).max(365).default(30),
  SEED_OWNER_NAME: z.string().default("Owner"),
  SEED_OWNER_EMAIL: z.string().default("owner@example.com"),
  SEED_OWNER_PASSWORD: z.string().optional(),
  SEED_WORKSPACE_NAME: z.string().default("Company Sites"),
  GEMINI_API_KEY: optionalString,
  GEMINI_LIVE_MODEL: z.string().default("gemini-3.8-live"),
  GEMINI_TEXT_MODEL: z.string().default("gemini-3.5-flash"),
  GROQ_API_KEY: optionalString,
  GROQ_STT_MODEL: z.string().default("whisper-large-v3-turbo"),
  GROQ_LLM_MODEL: z.string().default("llama-3.3-70b-versatile"),
  AI_MAX_SESSION_SECONDS: z.coerce.number().int().min(15).max(900).default(180),
  AI_MONTHLY_BUDGET_USD: z.coerce.number().min(0).default(0),
  AI_ALLOW_PAID_FALLBACK: boolFromEnv.default(false),
  TRANSCRIPT_RETENTION_ENABLED: boolFromEnv.default(false),
  AI_MONTHLY_SESSION_LIMIT: z.coerce.number().int().min(0).default(300),
  AI_MONTHLY_MINUTES_LIMIT: z.coerce.number().int().min(0).default(300),
  AI_FALLBACK_MAX_BYTES: z.coerce.number().int().min(1024).default(6 * 1024 * 1024),
  AI_FALLBACK_MAX_SECONDS: z.coerce.number().int().min(3).max(60).default(20),
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  const issues = parsed.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`).join(", ");
  throw new Error(`Invalid environment configuration: ${issues}`);
}

const raw = parsed.data;
const isProduction = raw.NODE_ENV === "production";

function isLocalDatabaseUrl(value: string | undefined): boolean {
  if (!value) return true;
  try {
    const host = new URL(value).hostname.toLowerCase();
    return host === "localhost" || host === "127.0.0.1" || host === "::1" || host === "[::1]";
  } catch {
    return false;
  }
}

const hasStrongAuthSecret = Boolean(raw.AUTH_SECRET && raw.AUTH_SECRET.length >= 16);
const localDatabase = isLocalDatabaseUrl(raw.DATABASE_URL);

// Session tokens are HMACed with AUTH_SECRET. The development fallback is public
// knowledge, so it must never protect a database that is not on this machine —
// otherwise a leaked database dump could be replayed against a live server.
if (!localDatabase && !hasStrongAuthSecret) {
  throw new Error(
    "AUTH_SECRET must be set to at least 16 characters when DATABASE_URL points at a non-local database.",
  );
}

const authSecret = hasStrongAuthSecret
  ? (raw.AUTH_SECRET as string)
  : isProduction
    ? (() => {
        throw new Error("AUTH_SECRET must be set to at least 16 characters in production.");
      })()
    : "development-only-insecure-auth-secret";

if (isProduction && !raw.DATABASE_URL) {
  throw new Error("DATABASE_URL is required in production.");
}

if (isProduction && raw.AI_ALLOW_PAID_FALLBACK) {
  // Paid AI is intentionally blocked at the configuration layer for this build.
  // Enabling it requires a code change + explicit client approval.
  throw new Error("AI_ALLOW_PAID_FALLBACK=true is not supported by this zero-cost build.");
}

export const env = {
  ...raw,
  isProduction,
  authSecret,
  databaseUrl: raw.DATABASE_URL ?? "postgresql://job_manager:job_manager@localhost:5432/job_manager",
  corsOrigins: raw.CORS_ORIGINS.split(",")
    .map((origin) => origin.trim())
    .filter(Boolean),
  ai: {
    geminiConfigured: Boolean(raw.GEMINI_API_KEY),
    groqConfigured: Boolean(raw.GROQ_API_KEY),
  },
} as const;

export type Env = typeof env;
