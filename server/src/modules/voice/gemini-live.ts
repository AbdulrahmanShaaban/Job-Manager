import { GoogleGenAI } from "@google/genai";
import { env } from "../../config/env.ts";
import { ApiError } from "../../shared/errors.ts";
import { logger } from "../../shared/logger.ts";
import { buildClientSetup, buildLiveConfig } from "./prompt.ts";

export interface LiveCredential {
  token: string;
  model: string;
  setup: ReturnType<typeof buildClientSetup>;
  expiresAt: string;
  newSessionExpireTime: string;
  maxSessionSeconds: number;
}

function client(): GoogleGenAI {
  if (!env.GEMINI_API_KEY) {
    throw new ApiError(
      503,
      "AI_UNAVAILABLE",
      "Voice assistant is not configured. Manual entry works normally.",
    );
  }
  return new GoogleGenAI({ apiKey: env.GEMINI_API_KEY });
}

/**
 * Creates a short-lived, single-use Live API token. The permanent Gemini key never
 * leaves the server. The token is locked to this model/config by the provider.
 */
export async function createLiveCredential(userName: string): Promise<LiveCredential> {
  const ai = client();
  const model = env.GEMINI_LIVE_MODEL;
  const expiresAt = new Date(Date.now() + 30 * 60 * 1000);
  const newSessionExpireTime = new Date(Date.now() + 2 * 60 * 1000);

  try {
    const token = await ai.authTokens.create({
      config: {
        uses: 1,
        expireTime: expiresAt.toISOString(),
        newSessionExpireTime: newSessionExpireTime.toISOString(),
        liveConnectConstraints: {
          model: model.startsWith("models/") ? model : `models/${model}`,
          config: buildLiveConfig(userName),
        },
      },
    });

    if (!token.name) {
      throw new Error("Gemini did not return an ephemeral token name");
    }

    return {
      token: token.name,
      model,
      setup: buildClientSetup(userName, model),
      expiresAt: expiresAt.toISOString(),
      newSessionExpireTime: newSessionExpireTime.toISOString(),
      maxSessionSeconds: env.AI_MAX_SESSION_SECONDS,
    };
  } catch (error) {
    logger.warn("Gemini Live token creation failed", {
      error: error instanceof Error ? error.message : String(error),
    });

    const message = error instanceof Error ? error.message : String(error);
    if (/quota|rate limit|resource_exhausted/i.test(message)) {
      throw new ApiError(
        429,
        "AI_QUOTA_EXHAUSTED",
        "Gemini Live is over its free limit right now. You can use the slower voice fallback or continue manually.",
      );
    }
    throw new ApiError(
      503,
      "AI_UNAVAILABLE",
      "Gemini Live could not start. Try the fallback voice mode or continue manually.",
    );
  }
}
