import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { PGlite } from "@electric-sql/pglite";

const migrationPath = fileURLToPath(
  new URL("../prisma/migrations/20261026000000_init/migration.sql", import.meta.url),
);

let db: PGlite;

beforeAll(async () => {
  db = new PGlite();
  await db.exec(readFileSync(migrationPath, "utf8"));
});

afterAll(async () => {
  await db.close();
});

describe("initial PostgreSQL migration", () => {
  it("creates every required table", async () => {
    const result = await db.query<{ table_name: string }>(
      "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name",
    );
    const names = result.rows.map((row) => row.table_name);
    for (const table of [
      "Invitation",
      "Session",
      "Site",
      "Task",
      "User",
      "Visit",
      "VoiceSession",
      "Workspace",
      "WorkspaceMember",
    ]) {
      expect(names).toContain(table);
    }
  });

  it("indexes visits by site and descending date", async () => {
    const result = await db.query<{ indexname: string }>(
      "SELECT indexname FROM pg_indexes WHERE tablename = 'Visit'",
    );
    const names = result.rows.map((row) => row.indexname);
    expect(names.some((name) => name.includes("siteId") && name.includes("visitDate"))).toBe(true);
  });

  it("stores date-only visits without shifting the calendar day", async () => {
    const user = await db.query<{ id: string }>(
      `INSERT INTO "User" (id, name, email, "passwordHash", "updatedAt")
       VALUES (gen_random_uuid(), 'Test', 'test@example.com', 'hash', now()) RETURNING id`,
    );
    const userId = user.rows[0]?.id;
    expect(userId).toBeTruthy();

    const site = await db.query<{ id: string }>(
      `INSERT INTO "Site" (id, name, scope, "createdById", address, "updatedAt")
       VALUES (gen_random_uuid(), 'قرنفل', 'PERSONAL', $1, 'المعادي', now()) RETURNING id`,
      [userId],
    );
    const siteId = site.rows[0]?.id;
    expect(siteId).toBeTruthy();

    await db.query(
      `INSERT INTO "Visit" (id, "siteId", "visitDate", "completedWork", "createdById", "updatedAt")
       VALUES (gen_random_uuid(), $1, '2026-10-26', 'تركيب كاميرتين', $2, now())`,
      [siteId, userId],
    );

    const visit = await db.query<{ day: string }>(
      `SELECT to_char("visitDate", 'YYYY-MM-DD') AS day FROM "Visit" WHERE "siteId" = $1`,
      [siteId],
    );
    expect(visit.rows[0]?.day).toBe("2026-10-26");
  });

  it("enforces idempotency via unique client operation ids", async () => {
    const user = await db.query<{ id: string }>(
      `INSERT INTO "User" (id, name, email, "passwordHash", "updatedAt")
       VALUES (gen_random_uuid(), 'Test2', 'test2@example.com', 'hash', now()) RETURNING id`,
    );
    const userId = user.rows[0]?.id;
    const site = await db.query<{ id: string }>(
      `INSERT INTO "Site" (id, name, scope, "createdById", address, "updatedAt")
       VALUES (gen_random_uuid(), 'صدره', 'PERSONAL', $1, 'العبور', now()) RETURNING id`,
      [userId],
    );
    const siteId = site.rows[0]?.id;
    const operationId = "11111111-1111-4111-8111-111111111111";

    await db.query(
      `INSERT INTO "Visit" (id, "siteId", "visitDate", "completedWork", "createdById", "clientOperationId", "updatedAt")
       VALUES (gen_random_uuid(), $1, '2026-10-26', 'أول', $2, $3, now())`,
      [siteId, userId, operationId],
    );

    await expect(
      db.query(
        `INSERT INTO "Visit" (id, "siteId", "visitDate", "completedWork", "createdById", "clientOperationId", "updatedAt")
         VALUES (gen_random_uuid(), $1, '2026-10-26', 'تاني', $2, $3, now())`,
        [siteId, userId, operationId],
      ),
    ).rejects.toBeTruthy();
  });

  it("enforces unique workspace membership", async () => {
    const user = await db.query<{ id: string }>(
      `INSERT INTO "User" (id, name, email, "passwordHash", "updatedAt")
       VALUES (gen_random_uuid(), 'Test3', 'test3@example.com', 'hash', now()) RETURNING id`,
    );
    const userId = user.rows[0]?.id;
    const workspace = await db.query<{ id: string }>(
      `INSERT INTO "Workspace" (id, name, "updatedAt") VALUES (gen_random_uuid(), 'شركة', now()) RETURNING id`,
    );
    const workspaceId = workspace.rows[0]?.id;

    await db.query(
      `INSERT INTO "WorkspaceMember" (id, "workspaceId", "userId", role)
       VALUES (gen_random_uuid(), $1, $2, 'OWNER')`,
      [workspaceId, userId],
    );

    await expect(
      db.query(
        `INSERT INTO "WorkspaceMember" (id, "workspaceId", "userId", role)
         VALUES (gen_random_uuid(), $1, $2, 'EDITOR')`,
        [workspaceId, userId],
      ),
    ).rejects.toBeTruthy();
  });
});
