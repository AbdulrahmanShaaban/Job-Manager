import { prisma } from "../../db/prisma.ts";
import { cairoWallClockToUtc, todayInCairo } from "../../shared/dates.ts";
import { ApiError } from "../../shared/errors.ts";
import { env } from "../../config/env.ts";

export function cairoMonthStart(now: Date = new Date()): Date {
  const today = todayInCairo(now);
  return cairoWallClockToUtc(`${today.slice(0, 7)}-01`, 0, 0);
}

export interface MonthlyUsage {
  sessions: number;
  seconds: number;
  minutes: number;
  monthStart: string;
  limits: {
    sessions: number;
    minutes: number;
    budgetUsd: number;
  };
  percentOfSessionLimit: number;
  percentOfMinuteLimit: number;
  warning: string | null;
}

export async function getMonthlyUsage(userId: string): Promise<MonthlyUsage> {
  const monthStart = cairoMonthStart();
  const aggregate = await prisma.voiceSession.aggregate({
    where: {
      userId,
      provider: { not: "NONE" },
      startedAt: { gte: monthStart },
    },
    _count: { _all: true },
    _sum: { estimatedSeconds: true },
  });

  const sessions = aggregate._count._all;
  const seconds = aggregate._sum.estimatedSeconds ?? 0;
  const minutes = Math.round((seconds / 60) * 10) / 10;
  const percentOfSessionLimit =
    env.AI_MONTHLY_SESSION_LIMIT > 0 ? Math.round((sessions / env.AI_MONTHLY_SESSION_LIMIT) * 100) : 0;
  const percentOfMinuteLimit =
    env.AI_MONTHLY_MINUTES_LIMIT > 0 ? Math.round((minutes / env.AI_MONTHLY_MINUTES_LIMIT) * 100) : 0;

  let warning: string | null = null;
  if (percentOfSessionLimit >= 80 || percentOfMinuteLimit >= 80) {
    warning = "استخدام المساعد الصوتي قرب من الحد الشهري. تقدر تكمل بالتسجيل اليدوي في أي وقت.";
  }

  return {
    sessions,
    seconds,
    minutes,
    monthStart: monthStart.toISOString(),
    limits: {
      sessions: env.AI_MONTHLY_SESSION_LIMIT,
      minutes: env.AI_MONTHLY_MINUTES_LIMIT,
      budgetUsd: env.AI_MONTHLY_BUDGET_USD,
    },
    percentOfSessionLimit,
    percentOfMinuteLimit,
    warning,
  };
}

/** Soft guard based on configurable free-tier estimates; never enables paid usage. */
export async function assertAiBudget(userId: string): Promise<void> {
  const usage = await getMonthlyUsage(userId);
  if (usage.limits.sessions > 0 && usage.sessions >= usage.limits.sessions) {
    throw new ApiError(
      429,
      "AI_QUOTA_EXHAUSTED",
      "The monthly voice limit configured for this workspace is used up. Continue manually; your draft is preserved.",
    );
  }
  if (usage.limits.minutes > 0 && usage.minutes >= usage.limits.minutes) {
    throw new ApiError(
      429,
      "AI_QUOTA_EXHAUSTED",
      "The monthly voice minutes limit is used up. Continue manually; your draft is preserved.",
    );
  }
}
