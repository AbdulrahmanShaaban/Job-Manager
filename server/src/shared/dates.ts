import { ApiError } from "./errors.ts";

export const CAIRO_TIME_ZONE = "Africa/Cairo";

const DATE_ONLY_RE = /^(\d{4})-(\d{2})-(\d{2})$/;

function pad(value: number): string {
  return String(value).padStart(2, "0");
}

/** Converts a stored PostgreSQL `date` value to a `YYYY-MM-DD` string without any timezone shift. */
export function formatDateOnly(date: Date): string {
  return `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())}`;
}

/** Parses `YYYY-MM-DD` into a UTC-midnight Date suitable for a PostgreSQL `date` column. */
export function parseDateOnly(value: string): Date {
  const match = DATE_ONLY_RE.exec(value.trim());
  if (!match) {
    throw ApiError.validation({ field: "date", message: "Expected a YYYY-MM-DD date" });
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    throw ApiError.validation({ field: "date", message: "That calendar date does not exist" });
  }
  return date;
}

function cairoParts(date: Date): {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
} {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: CAIRO_TIME_ZONE,
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).formatToParts(date);

  const get = (type: Intl.DateTimeFormatPartTypes): number => {
    const found = parts.find((part) => part.type === type);
    return found ? Number(found.value) : 0;
  };

  return {
    year: get("year"),
    month: get("month"),
    day: get("day"),
    hour: get("hour") === 24 ? 0 : get("hour"),
    minute: get("minute"),
    second: get("second"),
  };
}

/** Today's calendar date in Africa/Cairo (e.g. "2026-10-26"). */
export function todayInCairo(now: Date = new Date()): string {
  const parts = cairoParts(now);
  return `${parts.year}-${pad(parts.month)}-${pad(parts.day)}`;
}

function cairoOffsetMs(date: Date): number {
  const parts = cairoParts(date);
  const asUtc = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second);
  return asUtc - Math.floor(date.getTime() / 1000) * 1000;
}

/** Converts a Cairo wall-clock date/time to the matching UTC instant (DST-safe). */
export function cairoWallClockToUtc(day: string, hour = 0, minute = 0): Date {
  const { y, m, d } = splitDate(day);
  const guess = Date.UTC(y, m - 1, d, hour, minute, 0, 0);
  const offset1 = cairoOffsetMs(new Date(guess));
  let timestamp = guess - offset1;
  const offset2 = cairoOffsetMs(new Date(timestamp));
  if (offset2 !== offset1) {
    timestamp = guess - offset2;
  }
  return new Date(timestamp);
}

function splitDate(day: string): { y: number; m: number; d: number } {
  const parsed = parseDateOnly(day);
  return { y: parsed.getUTCFullYear(), m: parsed.getUTCMonth() + 1, d: parsed.getUTCDate() };
}

export function addDaysToDateOnly(day: string, days: number): string {
  const { y, m, d } = splitDate(day);
  const date = new Date(Date.UTC(y, m - 1, d + days));
  return formatDateOnly(date);
}

/** UTC window covering one Cairo calendar day, for querying timestamp columns. */
export function cairoDayBounds(day: string): { start: Date; end: Date } {
  return {
    start: cairoWallClockToUtc(day, 0, 0),
    end: cairoWallClockToUtc(addDaysToDateOnly(day, 1), 0, 0),
  };
}

export function isDateOnlyString(value: string): boolean {
  return DATE_ONLY_RE.test(value);
}
