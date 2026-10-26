import { Router } from "express";
import { z } from "zod";
import { prisma } from "../../db/prisma.ts";
import { env } from "../../config/env.ts";
import { ApiError } from "../../shared/errors.ts";
import { parseWith } from "../../shared/validation.ts";
import { requireAuth, authOf } from "../../middleware/auth.ts";
import { writeRateLimit } from "../../middleware/rate-limit.ts";
import { requireSiteAccess } from "../../shared/authz.ts";
import { serializeVisit } from "../../shared/serializers.ts";
import { parseDateOnly } from "../../shared/dates.ts";

export const visitsRouter = Router();
visitsRouter.use(requireAuth);

const uuidSchema = z.uuid();

const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .nullable()
    .optional()
    .transform((value) => (value === undefined ? undefined : value === null || value === "" ? null : value));

const dateOnlySchema = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);

const updateVisitSchema = z.object({
  visitDate: dateOnlySchema.optional(),
  completedWork: z.string().trim().min(1).max(5000).optional(),
  remainingWork: optionalText(5000),
  notes: optionalText(5000),
  transcript: optionalText(12000),
  // Required: see the concurrency note below.
  baseUpdatedAt: z.iso.datetime(),
});

visitsRouter.get("/:id", async (req, res) => {
  const auth = authOf(req);
  const visitId = parseWith(uuidSchema, req.params.id);

  const visit = await prisma.visit.findUnique({
    where: { id: visitId },
    include: { createdBy: { select: { id: true, name: true } } },
  });
  if (!visit) throw ApiError.notFound("Visit not found");

  await requireSiteAccess(auth.userId, visit.siteId, "read");
  res.json({ visit: serializeVisit(visit) });
});

/**
 * Visits are append-only by default. This endpoint is the explicit edit path:
 * it increments the revision and records `editedAt`; nothing rewrites silently.
 */
visitsRouter.patch("/:id", writeRateLimit, async (req, res) => {
  const auth = authOf(req);
  const visitId = parseWith(uuidSchema, req.params.id);

  const existing = await prisma.visit.findUnique({ where: { id: visitId } });
  if (!existing) throw ApiError.notFound("Visit not found");
  await requireSiteAccess(auth.userId, existing.siteId, "write");

  const body = parseWith(updateVisitSchema, req.body);
  const { baseUpdatedAt, visitDate, ...rest } = body;

  if (Object.keys(rest).length === 0 && !visitDate) {
    throw ApiError.badRequest("No changes supplied");
  }

  const expected = new Date(baseUpdatedAt);
  if (expected.getTime() !== existing.updatedAt.getTime()) {
    throw ApiError.conflict("This visit was edited on another device. Reload before saving.", {
      serverUpdatedAt: existing.updatedAt.toISOString(),
    });
  }

  const result = await prisma.visit.updateMany({
    where: { id: visitId, updatedAt: expected },
    data: {
      ...rest,
      ...(env.TRANSCRIPT_RETENTION_ENABLED ? {} : { transcript: null }),
      ...(visitDate ? { visitDate: parseDateOnly(visitDate) } : {}),
      revision: { increment: 1 },
      editedAt: new Date(),
    },
  });
  if (result.count === 0) {
    const current = await prisma.visit.findUnique({
      where: { id: visitId },
      select: { updatedAt: true },
    });
    throw ApiError.conflict("This visit was edited on another device. Reload before saving.", {
      serverUpdatedAt: (current?.updatedAt ?? existing.updatedAt).toISOString(),
    });
  }

  const visit = await prisma.visit.findUniqueOrThrow({
    where: { id: visitId },
    include: { createdBy: { select: { id: true, name: true } } },
  });

  res.json({ visit: serializeVisit(visit) });
});
