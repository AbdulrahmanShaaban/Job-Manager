import { beforeEach, describe, expect, it } from "vitest";
import {
  markProviderCooldown,
  providerCooldownRemainingMs,
  ProviderCallError,
  resetProviderCooldowns,
  tryProviders,
  tryProvidersDetailed,
} from "../src/modules/voice/provider-router.ts";
import { ApiError } from "../src/shared/errors.ts";

describe("provider router", () => {
  beforeEach(() => resetProviderCooldowns());

  it("falls through to the next free provider and reports which one succeeded", async () => {
    const result = await tryProvidersDetailed(
      [
        {
          key: "gemini:stt",
          run: async () => {
            throw new ProviderCallError("gemini:stt", "quota", {
              status: 429,
              quotaExhausted: true,
            });
          },
        },
        { key: "groq:stt", run: async () => "نص التجربة" },
      ],
      "unavailable",
    );

    expect(result.key).toBe("groq:stt");
    expect(result.value).toBe("نص التجربة");
    expect(providerCooldownRemainingMs("gemini:stt")).toBeGreaterThan(0);
  });

  it("does not spin: a cooling-down provider is skipped", async () => {
    markProviderCooldown("groq:llm", 60_000, "quota");
    let called = false;

    await expect(
      tryProviders(
        [
          {
            key: "groq:llm",
            run: async () => {
              called = true;
              return "should not run";
            },
          },
        ],
        "unavailable",
      ),
    ).rejects.toMatchObject({ code: "AI_UNAVAILABLE" });

    expect(called).toBe(false);
  });

  it("returns a quota error when every provider is exhausted", async () => {
    const quota = () =>
      Promise.reject(
        new ProviderCallError("x", "resource_exhausted", {
          status: 429,
          quotaExhausted: true,
        }),
      );

    await expect(
      tryProviders(
        [
          { key: "gemini:llm", run: quota },
          { key: "groq:llm", run: quota },
        ],
        "unavailable",
      ),
    ).rejects.toBeInstanceOf(ApiError);
  });

  it("treats 5xx errors as temporary and cools the provider down", async () => {
    await expect(
      tryProviders(
        [
          {
            key: "gemini:llm",
            run: async () => {
              throw new ProviderCallError("gemini:llm", "upstream error", { status: 503 });
            },
          },
        ],
        "unavailable",
      ),
    ).rejects.toMatchObject({ code: "AI_UNAVAILABLE" });

    expect(providerCooldownRemainingMs("gemini:llm")).toBeGreaterThan(0);
  });
});
