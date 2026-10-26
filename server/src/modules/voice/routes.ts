import express, { Router } from "express";
import { z } from "zod";
import { env } from "../../config/env.ts";
import { ApiError } from "../../shared/errors.ts";
import { parseWith } from "../../shared/validation.ts";
import { requireAuth, authOf } from "../../middleware/auth.ts";
import { voiceRateLimit } from "../../middleware/rate-limit.ts";
import { createLiveCredential } from "./gemini-live.ts";
import {
  finishLiveSession,
  processFallbackTurn,
  recordLiveSessionStart,
} from "./fallback-pipeline.ts";
import { executeTool, TOOL_NAMES } from "./tool-actions.ts";
import { getMonthlyUsage, assertAiBudget } from "./usage.ts";
import { assertFreeOnlyMode, providerCooldownSnapshot } from "./provider-router.ts";
import { prisma } from "../../db/prisma.ts";

export const voiceRouter = Router();
voiceRouter.use(requireAuth);

const uuid = z.uuid();

voiceRouter.post("/session-credential", voiceRateLimit, async (req, res) => {
  const auth = authOf(req);
  if (!env.GEMINI_API_KEY) {
    throw new ApiError(
      503,
      "AI_UNAVAILABLE",
      "Voice assistant is not configured. You can record visits manually.",
    );
  }

  // Zero-cost policy + monthly budget are enforced before any credential is
  // minted, so an exhausted budget cannot open a live socket.
  assertFreeOnlyMode();
  await assertAiBudget(auth.userId);

  const sessionId = await recordLiveSessionStart(auth.userId, env.GEMINI_LIVE_MODEL);

  try {
    const credential = await createLiveCredential(auth.user.name);
    res.status(201).json({
      sessionId,
      ...credential,
      transcriptRetentionEnabled: env.TRANSCRIPT_RETENTION_ENABLED,
    });
  } catch (error) {
    await finishLiveSession(auth.userId, sessionId, {
      status: "FAILED",
      errorCode: error instanceof ApiError ? error.code : "AI_UNAVAILABLE",
    });
    throw error;
  }
});

voiceRouter.post("/sessions/:id/complete", voiceRateLimit, async (req, res) => {
  const auth = authOf(req);
  const sessionId = parseWith(uuid, req.params.id);
  const body = parseWith(
    z.object({
      status: z.enum(["COMPLETED", "FAILED", "ABANDONED"]),
      summary: z.string().trim().max(500).nullable().optional(),
      transcript: z.string().max(20000).nullable().optional(),
      estimatedSeconds: z.coerce.number().int().min(0).max(3600).optional(),
      errorCode: z.string().max(80).nullable().optional(),
    }),
    req.body,
  );

  await finishLiveSession(auth.userId, sessionId, body);
  res.json({ usage: await getMonthlyUsage(auth.userId) });
});

voiceRouter.post("/tool", voiceRateLimit, async (req, res) => {
  const auth = authOf(req);
  const body = parseWith(
    z.object({
      name: z.enum(TOOL_NAMES),
      args: z.record(z.string(), z.unknown()).default({}),
      sessionId: uuid.optional(),
    }),
    req.body,
  );

  if (body.sessionId) {
    const session = await prisma.voiceSession.findUnique({ where: { id: body.sessionId } });
    if (!session || session.userId !== auth.userId) {
      throw ApiError.notFound("Voice session not found");
    }
  }

  const result = await executeTool(auth.userId, body.name, body.args);
  res.json({ result });
});

voiceRouter.post(
  "/fallback-turn",
  voiceRateLimit,
  express.raw({
    type: ["audio/*", "application/octet-stream"],
    limit: env.AI_FALLBACK_MAX_BYTES,
  }),
  async (req, res) => {
    const auth = authOf(req);
    if (!Buffer.isBuffer(req.body) || req.body.length === 0) {
      throw new ApiError(400, "BAD_REQUEST", "Send a short audio recording in the request body.");
    }

    const mimeType = req.header("content-type")?.split(";")[0]?.trim() ?? "audio/wav";
    if (!mimeType.startsWith("audio/") && mimeType !== "application/octet-stream") {
      throw new ApiError(415, "BAD_REQUEST", "Unsupported audio content type.");
    }

    const query = parseWith(
      z.object({
        durationSeconds: z.coerce
          .number()
          .min(0.5)
          .max(env.AI_FALLBACK_MAX_SECONDS)
          .optional(),
      }),
      req.query,
    );

    // Never trust the client-reported duration alone: a large upload implies a
    // longer recording than the client claims, which would under-count usage.
    const byteEstimateSeconds = req.body.length / 32000;
    const durationSeconds = Math.min(
      env.AI_FALLBACK_MAX_SECONDS,
      Math.max(query.durationSeconds ?? 0, byteEstimateSeconds),
    );

    const result = await processFallbackTurn({
      userId: auth.userId,
      userName: auth.user.name,
      audio: req.body,
      mimeType,
      durationSeconds: Math.round(durationSeconds * 10) / 10,
    });

    res.json(result);
  },
);

voiceRouter.get("/usage", async (req, res) => {
  const auth = authOf(req);
  const usage = await getMonthlyUsage(auth.userId);

  res.json({
    usage,
    capabilities: {
      geminiLive: env.ai.geminiConfigured,
      fallbackStt: env.ai.groqConfigured || env.ai.geminiConfigured,
      fallbackLlm: env.ai.groqConfigured || env.ai.geminiConfigured,
      transcriptRetentionEnabled: env.TRANSCRIPT_RETENTION_ENABLED,
      paidFallbackAllowed: env.AI_ALLOW_PAID_FALLBACK,
      budgetUsd: env.AI_MONTHLY_BUDGET_USD,
      maxSessionSeconds: env.AI_MAX_SESSION_SECONDS,
      fallbackMaxSeconds: env.AI_FALLBACK_MAX_SECONDS,
    },
    cooldowns: providerCooldownSnapshot(),
  });
});
