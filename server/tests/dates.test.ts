import { describe, expect, it } from "vitest";
import {
  addDaysToDateOnly,
  cairoDayBounds,
  cairoWallClockToUtc,
  formatDateOnly,
  parseDateOnly,
  todayInCairo,
} from "../src/shared/dates.ts";

describe("date-only handling", () => {
  it("round-trips a calendar date without timezone drift", () => {
    const date = parseDateOnly("2026-10-26");
    expect(formatDateOnly(date)).toBe("2026-10-26");
    expect(date.toISOString()).toBe("2026-10-26T00:00:00.000Z");
  });

  it("rejects impossible dates", () => {
    expect(() => parseDateOnly("2026-02-30")).toThrow();
    expect(() => parseDateOnly("26-10-2026")).toThrow();
    expect(() => parseDateOnly("2026-13-01")).toThrow();
  });

  it("computes today in Cairo around the UTC midnight boundary", () => {
    // 22:30 UTC on 25 Oct is 01:30 on 26 Oct in Cairo (EEST, UTC+3).
    expect(todayInCairo(new Date("2026-10-25T22:30:00.000Z"))).toBe("2026-10-26");
    expect(todayInCairo(new Date("2026-10-25T20:59:00.000Z"))).toBe("2026-10-25");
  });

  it("uses the correct Cairo offset in summer and winter", () => {
    const summer = cairoDayBounds("2026-07-15");
    expect(summer.start.toISOString()).toBe("2026-07-14T21:00:00.000Z");
    expect(summer.end.toISOString()).toBe("2026-07-15T21:00:00.000Z");

    const winter = cairoDayBounds("2026-01-15");
    expect(winter.start.toISOString()).toBe("2026-01-14T22:00:00.000Z");
    expect(winter.end.toISOString()).toBe("2026-01-15T22:00:00.000Z");
  });

  it("adds days across month and year boundaries", () => {
    expect(addDaysToDateOnly("2026-10-31", 1)).toBe("2026-11-01");
    expect(addDaysToDateOnly("2026-12-31", 1)).toBe("2027-01-01");
    expect(addDaysToDateOnly("2026-03-01", -1)).toBe("2026-02-28");
  });

  it("converts a Cairo wall clock to UTC", () => {
    expect(cairoWallClockToUtc("2026-10-26", 9, 30).toISOString()).toBe(
      "2026-10-26T06:30:00.000Z",
    );
  });
});
