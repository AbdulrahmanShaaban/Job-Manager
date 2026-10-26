import { Router } from "express";
import { z } from "zod";
import { prisma } from "../../db/prisma.ts";
import { ApiError } from "../../shared/errors.ts";
import { parseWith } from "../../shared/validation.ts";
import { requireAuth, authOf } from "../../middleware/auth.ts";
import { writeRateLimit } from "../../middleware/rate-limit.ts";
import { requireSiteAccess, requireTaskAccess } from "../../shared/authz.ts";
import { serializeTask } from "../../shared/serializers.ts";
import { parseDateOnly } from "../../shared/dates.ts";
import type { Prisma, TaskStatus } from "../../generated/prisma/client.ts";

export const tasksRouter = Router();
tasksRouter.use(requireAuth);

const uuidSchema = z.uuid();
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
  }, "That calendar date does not exist");

const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .nullable()
    .optional()
    .transform((value) => (value === undefined ? undefined : value === null || value === "" ? null : value));

const createTaskSchema = z.object({
  siteId: uuidSchema.optional(),
  title: z.string().trim().min(1).max(200),
  description: optionalText(2000),
  status: z.enum(["OPEN", "IN_PROGRESS", "DONE"]).default("OPEN"),
  priority: z.enum(["LOW", "NORMAL", "HIGH"]).default("NORMAL"),
  dueDate: dateOnlySchema.nullable().optional(),
  assigneeId: uuidSchema.nullable().optional(),
  operationId: uuidSchema.optional(),
});

const updateTaskSchema = z.object({
  title: z.string().trim().min(1).max(200).optional(),
  description: optionalText(2000),
  status: z.enum(["OPEN", "IN_PROGRESS", "DONE"]).optional(),
  priority: z.enum(["LOW", "NORMAL", "HIGH"]).optional(),
  dueDate: dateOnlySchema.nullable().optional(),
  assigneeId: uuidSchema.nullable().optional(),
  // Required: a PATCH without it would silently overwrite a colleague's edit.
  baseUpdatedAt: z.iso.datetime(),
});

const taskInclude = {
  site: { select: { id: true, name: true, scope: true } },
  assignee: { select: { id: true, name: true } },
};

async function accessibleWorkspaceIds(userId: string): Promise<string[]> {
  const memberships = await prisma.workspaceMember.findMany({
    where: { userId },
    select: { workspaceId: true },
  });
  return memberships.map((membership) => membership.workspaceId);
}

async function validateAssignee(
  userId: string,
  siteId: string | null | undefined,
  assigneeId: string | null | undefined,
): Promise<void> {
  if (!assigneeId || assigneeId === userId) return;

  if (!siteId) {
    throw ApiError.validation({
      field: "assigneeId",
      message: "A task without a site can only be assigned to you",
    });
  }

  const site = await prisma.site.findUnique({ where: { id: siteId } });
  if (!site) throw ApiError.notFound("Site not found");

  if (site.scope === "PERSONAL") {
    throw ApiError.validation({
      field: "assigneeId",
      message: "Personal-site tasks can only be assigned to the owner",
    });
  }

  if (!site.workspaceId) throw ApiError.badRequest("Company site has no workspace");

  const membership = await prisma.workspaceMember.findUnique({
    where: { workspaceId_userId: { workspaceId: site.workspaceId, userId: assigneeId } },
  });
  if (!membership) {
    throw ApiError.validation({
      field: "assigneeId",
      message: "That person is not a member of this workspace",
    });
  }
}

tasksRouter.get("/", async (req, res) => {
  const auth = authOf(req);
  const query = parseWith(
    z.object({
      siteId: uuidSchema.optional(),
      status: z.string().optional(),
      assigneeId: z.union([z.literal("me"), uuidSchema]).optional(),
      q: z.string().trim().max(120).optional(),
      limit: z.coerce.number().int().min(1).max(300).default(100),
    }),
    req.query,
  );

  const allowedStatuses: TaskStatus[] = ["OPEN", "IN_PROGRESS", "DONE"];
  const statuses = query.status
    ? (query.status.split(",").map((value) => value.trim()) as TaskStatus[])
    : undefined;
  if (statuses?.some((status) => !allowedStatuses.includes(status))) {
    throw ApiError.validation({ field: "status", message: "Unknown task status" });
  }

  if (query.siteId) {
    await requireSiteAccess(auth.userId, query.siteId, "read");
  }

  const term = query.q ? query.q.replace(/[%_\\]/g, " ").trim() : "";
  const workspaceIds = await accessibleWorkspaceIds(auth.userId);
  const accessOr = [
    {
      siteId: { not: null },
      site: {
        is: {
          OR: [
            { scope: "PERSONAL" as const, ownerUserId: auth.userId },
            { scope: "COMPANY" as const, workspaceId: { in: workspaceIds } },
          ],
        },
      },
    },
    {
      siteId: null,
      OR: [{ createdById: auth.userId }, { assigneeId: auth.userId }],
    },
  ];

  const tasks = await prisma.task.findMany({
    where: {
      AND: [
        query.siteId ? { siteId: query.siteId } : { OR: accessOr },
        statuses ? { status: { in: statuses } } : {},
        query.assigneeId
          ? { assigneeId: query.assigneeId === "me" ? auth.userId : query.assigneeId }
          : {},
        query.q
          ? {
              OR: [
                { title: { contains: term, mode: "insensitive" } },
                { description: { contains: term, mode: "insensitive" } },
              ],
            }
          : {},
      ],
    },
    include: taskInclude,
    orderBy: [
      { status: "asc" },
      { priority: "desc" },
      { dueDate: { sort: "asc", nulls: "last" } },
      { createdAt: "desc" },
    ],
    take: query.limit,
  });

  res.json({ tasks: tasks.map(serializeTask) });
});

tasksRouter.post("/", writeRateLimit, async (req, res) => {
  const auth = authOf(req);
  const body = parseWith(createTaskSchema, req.body);

  if (body.siteId) {
    await requireSiteAccess(auth.userId, body.siteId, "write");
  }
  await validateAssignee(auth.userId, body.siteId, body.assigneeId);

  if (body.operationId) {
    const existing = await prisma.task.findUnique({
      where: { clientOperationId: body.operationId },
      include: taskInclude,
    });
    if (existing) {
      // Authorise through the same helper every other task read uses, so the
      // replay grant has one source of truth.
      await requireTaskAccess(auth.userId, existing.id, "read");
      res.status(200).json({ task: serializeTask(existing), replayed: true });
      return;
    }
  }

  const now = new Date();
  const task = await prisma.task.create({
    data: {
      siteId: body.siteId ?? null,
      title: body.title,
      description: body.description ?? null,
      status: body.status,
      priority: body.priority,
      dueDate: body.dueDate ? parseDateOnly(body.dueDate) : null,
      completedAt: body.status === "DONE" ? now : null,
      createdById: auth.userId,
      assigneeId: body.assigneeId ?? null,
      clientOperationId: body.operationId ?? null,
    },
    include: taskInclude,
  });

  res.status(201).json({ task: serializeTask(task) });
});

tasksRouter.patch("/:id", writeRateLimit, async (req, res) => {
  const auth = authOf(req);
  const taskId = parseWith(uuidSchema, req.params.id);
  const { task } = await requireTaskAccess(auth.userId, taskId, "write");
  const body = parseWith(updateTaskSchema, req.body);

  const { baseUpdatedAt, dueDate, assigneeId, status, ...rest } = body;
  if (
    Object.keys(rest).length === 0 &&
    dueDate === undefined &&
    assigneeId === undefined &&
    status === undefined
  ) {
    throw ApiError.badRequest("No changes supplied");
  }

  if (baseUpdatedAt && task.updatedAt.getTime() !== new Date(baseUpdatedAt).getTime()) {
    throw ApiError.conflict("This task was updated on another device. Reload before saving.", {
      serverUpdatedAt: task.updatedAt.toISOString(),
    });
  }

  if (assigneeId !== undefined) {
    await validateAssignee(auth.userId, task.siteId, assigneeId);
  }

  const data: Prisma.TaskUncheckedUpdateInput = { ...rest };
  if (dueDate !== undefined) data.dueDate = dueDate ? parseDateOnly(dueDate) : null;
  if (assigneeId !== undefined) data.assigneeId = assigneeId;
  if (status !== undefined) {
    data.status = status;
    if (status === "DONE" && task.status !== "DONE") data.completedAt = new Date();
    if (status !== "DONE" && task.status === "DONE") data.completedAt = null;
  }

  // Conditional write: the expected version travels in the WHERE clause, so
  // two concurrent PATCHes carrying the same baseUpdatedAt cannot both win.
  const result = await prisma.task.updateMany({
    where: { id: taskId, updatedAt: new Date(baseUpdatedAt) },
    data,
  });
  if (result.count === 0) {
    const current = await prisma.task.findUnique({
      where: { id: taskId },
      select: { updatedAt: true },
    });
    throw ApiError.conflict("This task was updated on another device. Reload before saving.", {
      serverUpdatedAt: (current?.updatedAt ?? task.updatedAt).toISOString(),
    });
  }

  const updated = await prisma.task.findUniqueOrThrow({
    where: { id: taskId },
    include: taskInclude,
  });

  res.json({ task: serializeTask(updated) });
});

tasksRouter.delete("/:id", writeRateLimit, async (req, res) => {
  const auth = authOf(req);
  const taskId = parseWith(uuidSchema, req.params.id);
  await requireTaskAccess(auth.userId, taskId, "write");
  await prisma.task.delete({ where: { id: taskId } });
  res.status(204).end();
});
