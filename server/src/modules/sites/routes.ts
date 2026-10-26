import { Router } from "express";
import { z } from "zod";
import { prisma } from "../../db/prisma.ts";
import { ApiError } from "../../shared/errors.ts";
import { parseWith } from "../../shared/validation.ts";
import { requireAuth, authOf } from "../../middleware/auth.ts";
import { writeRateLimit } from "../../middleware/rate-limit.ts";
import {
  getSiteAccess,
  requireSiteAccess,
  requireWorkspaceRole,
} from "../../shared/authz.ts";
import { serializeSite, serializeTask, serializeVisit } from "../../shared/serializers.ts";

export const sitesRouter = Router();
sitesRouter.use(requireAuth);

const uuidSchema = z.uuid();
const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .nullable()
    .optional()
    .transform((value) => (value === undefined ? undefined : value === null || value === "" ? null : value));

const httpUrl = z
  .string()
  .trim()
  .max(2048)
  .refine((value) => {
    try {
      const url = new URL(value);
      return url.protocol === "http:" || url.protocol === "https:";
    } catch {
      return false;
    }
  }, "Enter a valid http(s) link");

const optionalUrl = z
  .union([httpUrl, z.literal(""), z.null()])
  .optional()
  .transform((value) => (value === undefined ? undefined : value === "" || value === null ? null : value));

const createSiteSchema = z.object({
  name: z.string().trim().min(1).max(160),
  scope: z.enum(["PERSONAL", "COMPANY"]),
  workspaceId: uuidSchema.optional(),
  address: z.string().trim().min(1).max(400),
  contactName: optionalText(120),
  contactPhone: optionalText(40),
  mapUrl: optionalUrl,
  latitude: z.number().min(-90).max(90).nullable().optional(),
  longitude: z.number().min(-180).max(180).nullable().optional(),
  generalNotes: optionalText(5000),
  operationId: uuidSchema.optional(),
});

const updateSiteSchema = z.object({
  name: z.string().trim().min(1).max(160).optional(),
  address: z.string().trim().min(1).max(400).optional(),
  contactName: optionalText(120),
  contactPhone: optionalText(40),
  mapUrl: optionalUrl,
  latitude: z.number().min(-90).max(90).nullable().optional(),
  longitude: z.number().min(-180).max(180).nullable().optional(),
  generalNotes: optionalText(5000),
  status: z.enum(["ACTIVE", "ARCHIVED"]).optional(),
  // Required: a PATCH without it would silently overwrite a colleague's edit.
  baseUpdatedAt: z.iso.datetime(),
});

async function workspaceIdsFor(userId: string): Promise<string[]> {
  const memberships = await prisma.workspaceMember.findMany({
    where: { userId },
    select: { workspaceId: true },
  });
  return memberships.map((membership) => membership.workspaceId);
}

function accessFilter(userId: string, workspaceIds: string[]) {
  return [
    { scope: "PERSONAL" as const, ownerUserId: userId },
    { scope: "COMPANY" as const, workspaceId: { in: workspaceIds } },
  ];
}

const siteListInclude = {
  workspace: { select: { id: true, name: true } },
  visits: { orderBy: [{ visitDate: "desc" as const }, { createdAt: "desc" as const }], take: 1 },
  _count: { select: { tasks: { where: { status: { not: "DONE" as const } } } } },
};

/**
 * `contains` is an ILIKE pattern, so `%` and `_` in user input act as
 * wildcards (and `%` forces a sequential scan). Strip them.
 */
function searchTerm(value: string): string {
  return value.replace(/[%_\\]/g, " ").trim();
}

sitesRouter.get("/", async (req, res) => {
  const auth = authOf(req);
  const query = parseWith(
    z.object({
      scope: z.enum(["PERSONAL", "COMPANY"]).optional(),
      status: z.enum(["ACTIVE", "ARCHIVED"]).optional(),
      q: z.string().trim().max(120).optional(),
      limit: z.coerce.number().int().min(1).max(200).default(100),
    }),
    req.query,
  );

  const term = query.q ? searchTerm(query.q) : "";
  const workspaceIds = await workspaceIdsFor(auth.userId);
  const scopeFilter =
    query.scope === "PERSONAL"
      ? { scope: "PERSONAL" as const, ownerUserId: auth.userId }
      : query.scope === "COMPANY"
        ? { scope: "COMPANY" as const, workspaceId: { in: workspaceIds } }
        : { OR: accessFilter(auth.userId, workspaceIds) };

  const sites = await prisma.site.findMany({
    where: {
      AND: [
        scopeFilter,
        query.status ? { status: query.status } : {},
        term
          ? {
              OR: [
                { name: { contains: term, mode: "insensitive" } },
                { address: { contains: term, mode: "insensitive" } },
                { generalNotes: { contains: term, mode: "insensitive" } },
              ],
            }
          : {},
      ],
    },
    include: siteListInclude,
    orderBy: { updatedAt: "desc" },
    take: query.limit,
  });

  res.json({ sites: sites.map(serializeSite) });
});

sitesRouter.post("/", writeRateLimit, async (req, res) => {
  const auth = authOf(req);
  const body = parseWith(createSiteSchema, req.body);

  if (body.scope === "COMPANY") {
    if (!body.workspaceId) {
      throw ApiError.validation({ field: "workspaceId", message: "Company sites need a workspace" });
    }
    await requireWorkspaceRole(auth.userId, body.workspaceId, "write");
  } else if (body.workspaceId) {
    throw ApiError.validation({
      field: "workspaceId",
      message: "Personal sites cannot belong to a workspace",
    });
  }

  if (body.operationId) {
    const existing = await prisma.site.findUnique({
      where: { clientOperationId: body.operationId },
      include: siteListInclude,
    });
    if (existing) {
      const access = await getSiteAccess(auth.userId, existing);
      if (access.canRead) {
        res.status(200).json({ site: serializeSite(existing), replayed: true });
        return;
      }
      throw ApiError.conflict("That operation belongs to another account");
    }
  }

  const site = await prisma.site.create({
    data: {
      name: body.name,
      scope: body.scope,
      workspaceId: body.scope === "COMPANY" ? body.workspaceId : null,
      ownerUserId: body.scope === "PERSONAL" ? auth.userId : null,
      createdById: auth.userId,
      address: body.address,
      contactName: body.contactName ?? null,
      contactPhone: body.contactPhone ?? null,
      mapUrl: body.mapUrl ?? null,
      latitude: body.latitude ?? null,
      longitude: body.longitude ?? null,
      generalNotes: body.generalNotes ?? null,
      clientOperationId: body.operationId ?? null,
    },
    include: siteListInclude,
  });

  res.status(201).json({ site: serializeSite(site) });
});

sitesRouter.get("/:id", async (req, res) => {
  const auth = authOf(req);
  const siteId = parseWith(uuidSchema, req.params.id);
  const access = await requireSiteAccess(auth.userId, siteId, "read");

  const site = await prisma.site.findUnique({
    where: { id: siteId },
    include: {
      workspace: { select: { id: true, name: true } },
      tasks: {
        orderBy: [{ status: "asc" }, { priority: "desc" }, { createdAt: "desc" }],
        include: { assignee: { select: { id: true, name: true } } },
      },
      visits: {
        orderBy: [{ visitDate: "desc" }, { createdAt: "desc" }],
        take: 10,
        include: { createdBy: { select: { id: true, name: true } } },
      },
      _count: { select: { tasks: { where: { status: { not: "DONE" } } } } },
    },
  });

  if (!site) throw ApiError.notFound("Site not found");

  res.json({
    site: {
      ...serializeSite(site),
      tasks: site.tasks.map((task) => serializeTask(task)),
      visits: site.visits.map((visit) => serializeVisit(visit)),
    },
    access: {
      role: access.workspaceRole,
      canWrite: access.canWrite,
      canManage: access.canManage,
    },
  });
});

sitesRouter.patch("/:id", writeRateLimit, async (req, res) => {
  const auth = authOf(req);
  const siteId = parseWith(uuidSchema, req.params.id);
  const access = await requireSiteAccess(auth.userId, siteId, "write");
  const body = parseWith(updateSiteSchema, req.body);

  const { baseUpdatedAt, ...updates } = body;
  if (Object.keys(updates).length === 0) {
    throw ApiError.badRequest("No changes supplied");
  }

  // Conditional write: the WHERE clause carries the expected version, so two
  // concurrent PATCHes with the same baseUpdatedAt cannot both succeed.
  const expected = new Date(baseUpdatedAt);
  if (expected.getTime() !== access.site.updatedAt.getTime()) {
    throw ApiError.conflict("This site was updated on another device. Reload before saving.", {
      serverUpdatedAt: access.site.updatedAt.toISOString(),
    });
  }

  const result = await prisma.site.updateMany({
    where: { id: siteId, updatedAt: expected },
    data: updates,
  });
  if (result.count === 0) {
    const current = await prisma.site.findUnique({
      where: { id: siteId },
      select: { updatedAt: true },
    });
    throw ApiError.conflict("This site was updated on another device. Reload before saving.", {
      serverUpdatedAt: (current?.updatedAt ?? access.site.updatedAt).toISOString(),
    });
  }

  const site = await prisma.site.findUniqueOrThrow({
    where: { id: siteId },
    include: siteListInclude,
  });

  res.json({ site: serializeSite(site) });
});
