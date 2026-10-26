import { ApiError } from "../../shared/errors.ts";
import { env } from "../../config/env.ts";

export class ProviderCallError extends Error {
  readonly provider: string;
  readonly status: number | undefined;
  readonly quotaExhausted: boolean;
  readonly retryable: boolean;

  constructor(
    provider: string,
    message: string,
    options: { status?: number; quotaExhausted?: boolean; retryable?: boolean } = {},
  ) {
    super(message);
    this.name = "ProviderCallError";
    this.provider = provider;
    this.status = options.status;
    this.quotaExhausted = options.quotaExhausted ?? false;
    this.retryable = options.retryable ?? true;
  }
}

interface Cooldown {
  until: number;
  reason: string;
}

const cooldowns = new Map<string, Cooldown>();

export function providerCooldownRemainingMs(key: string): number {
  const entry = cooldowns.get(key);
  if (!entry) return 0;
  const remaining = entry.until - Date.now();
  if (remaining <= 0) {
    cooldowns.delete(key);
    return 0;
  }
  return remaining;
}

export function markProviderCooldown(key: string, ms: number, reason: string): void {
  cooldowns.set(key, { until: Date.now() + ms, reason });
}

export function resetProviderCooldowns(): void {
  cooldowns.clear();
}

export function providerCooldownSnapshot(): Record<string, { secondsRemaining: number; reason: string }> {
  const snapshot: Record<string, { secondsRemaining: number; reason: string }> = {};
  for (const [key, entry] of cooldowns) {
    const remaining = entry.until - Date.now();
    if (remaining > 0) {
      snapshot[key] = { secondsRemaining: Math.ceil(remaining / 1000), reason: entry.reason };
    }
  }
  return snapshot;
}

export function classifyProviderFailure(
  provider: string,
  status: number | undefined,
  message: string,
): ProviderCallError {
  const quotaExhausted = status === 429 || /quota|rate limit|resource_exhausted/i.test(message);
  const authFailure = status === 401 || status === 403;
  return new ProviderCallError(provider, message, {
    status,
    quotaExhausted,
    retryable: quotaExhausted || authFailure || (status ?? 0) >= 500,
  });
}

export function assertFreeOnlyMode(): void {
  if (env.AI_ALLOW_PAID_FALLBACK) {
    throw new ApiError(
      403,
      "AI_NOT_ALLOWED",
      "Paid AI fallback is disabled by the zero-cost policy for this build.",
    );
  }
}

interface ProviderAttempt<T> {
  key: string;
  run: () => Promise<T>;
}

/**
 * Tries each configured free provider at most once, skipping any provider that is
 * cooling down after a quota/auth/outage failure. No retry loops.
 */
export async function tryProvidersDetailed<T>(
  attempts: ProviderAttempt<T>[],
  unavailableMessage: string,
): Promise<{ value: T; key: string }> {
  assertFreeOnlyMode();
  let lastError: ProviderCallError | undefined;
  let quotaFailures = 0;

  for (const attempt of attempts) {
    const cooldownMs = providerCooldownRemainingMs(attempt.key);
    if (cooldownMs > 0) continue;

    try {
      const value = await attempt.run();
      return { value, key: attempt.key };
    } catch (error) {
      const failure =
        error instanceof ProviderCallError
          ? error
          : classifyProviderFailure(attempt.key, undefined, error instanceof Error ? error.message : String(error));

      lastError = failure;
      if (failure.quotaExhausted) {
        quotaFailures += 1;
        markProviderCooldown(attempt.key, 15 * 60 * 1000, "quota");
      } else if (failure.retryable) {
        markProviderCooldown(attempt.key, 60 * 1000, "provider-error");
      }
    }
  }

  if (lastError) {
    if (quotaFailures > 0 && quotaFailures === attempts.length) {
      throw new ApiError(
        429,
        "AI_QUOTA_EXHAUSTED",
        "All free AI providers reached their limits. Your draft is safe — continue manually.",
      );
    }
    throw new ApiError(503, "AI_UNAVAILABLE", unavailableMessage, {
      lastProvider: lastError.provider,
    });
  }

  throw new ApiError(
    503,
    "AI_UNAVAILABLE",
    "Voice is cooling down after a provider limit. Continue manually for now.",
  );
}

export async function tryProviders<T>(
  attempts: ProviderAttempt<T>[],
  unavailableMessage: string,
): Promise<T> {
  const result = await tryProvidersDetailed(attempts, unavailableMessage);
  return result.value;
}
