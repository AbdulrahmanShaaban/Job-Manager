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
import { parseDateOnly, todayInCairo } from "../../shared/dates.ts";

export const sitesVisitsRouter = Router({ mergeParams: true });
sitesVisitsRouter.use(requireAuth);

const uuidSchema = z.uuid();

const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .nullable()
    .optional()
    .transform((value) => (value === undefined ? undefined : value === null || value === "" ? null : value));

const dateOnlySchema = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, "Use a YYYY-MM-DD date")
  .refine((value) => {
    try {
      parseDateOnly(value);
      return true;
    } catch {
      return false;
    }
  }, "That calendar date does not exist")
  .refine((value) => {
    // A 9999 date sorts to the top of every history and dashboard query.
    const year = Number(value.slice(0, 4));
    const currentYear = Number(todayInCairo().slice(0, 4));
    return year >= 2000 && year <= currentYear + 1;
  }, "That date is outside the supported range");

const createVisitSchema = z.object({
  visitDate: dateOnlySchema.optional(),
  completedWork: z.string().trim().min(1).max(5000),
  remainingWork: optionalText(5000),
  notes: optionalText(5000),
  transcript: optionalText(12000),
  source: z.enum(["MANUAL", "VOICE"]).default("MANUAL"),
  operationId: uuidSchema.optional(),
});

sitesVisitsRouter.get("/:id/visits", async (req, res) => {
  const auth = authOf(req);
  const siteId = parseWith(uuidSchema, req.params.id);
  await requireSiteAccess(auth.userId, siteId, "read");

  const query = parseWith(
    z.object({
      from: dateOnlySchema.optional(),
      to: dateOnlySchema.optional(),
      limit: z.coerce.number().int().min(1).max(200).default(50),
      cursor: uuidSchema.optional(),
    }),
    req.query,
  );

  const visits = await prisma.visit.findMany({
    where: {
      siteId,
      ...(query.from || query.to
        ? {
            visitDate: {
              ...(query.from ? { gte: parseDateOnly(query.from) } : {}),
              ...(query.to ? { lte: parseDateOnly(query.to) } : {}),
            },
          }
        : {}),
    },
    include: { createdBy: { select: { id: true, name: true } } },
    orderBy: [{ visitDate: "desc" }, { createdAt: "desc" }, { id: "desc" }],
    take: query.limit + 1,
    ...(query.cursor ? { cursor: { id: query.cursor }, skip: 1 } : {}),
  });

  const hasMore = visits.length > query.limit;
  const page = hasMore ? visits.slice(0, query.limit) : visits;
  const last = page.at(-1);

  res.json({
    visits: page.map(serializeVisit),
    nextCursor: hasMore && last ? last.id : null,
  });
});

sitesVisitsRouter.post("/:id/visits", writeRateLimit, async (req, res) => {
  const auth = authOf(req);
  const siteId = parseWith(uuidSchema, req.params.id);
  await requireSiteAccess(auth.userId, siteId, "write");
  const body = parseWith(createVisitSchema, req.body);

  if (body.operationId) {
    const existing = await prisma.visit.findUnique({
      where: { clientOperationId: body.operationId },
      include: { createdBy: { select: { id: true, name: true } } },
    });
    if (existing) {
      if (existing.siteId !== siteId) {
        throw ApiError.conflict("That operation belongs to a different site");
      }
      res.status(200).json({ visit: serializeVisit(existing), replayed: true });
      return;
    }
  }

  const visit = await prisma.visit.create({
    data: {
      siteId,
      visitDate: parseDateOnly(body.visitDate ?? todayInCairo()),
      completedWork: body.completedWork,
      remainingWork: body.remainingWork ?? null,
      notes: body.notes ?? null,
      // Retention is a server-side policy: a client cannot opt itself into
      // storing speech text while the deployment says retention is off.
      transcript: env.TRANSCRIPT_RETENTION_ENABLED ? (body.transcript ?? null) : null,
      source: body.source,
      createdById: auth.userId,
      clientOperationId: body.operationId ?? null,
    },
    include: { createdBy: { select: { id: true, name: true } } },
  });

  res.status(201).json({ visit: serializeVisit(visit) });
});
