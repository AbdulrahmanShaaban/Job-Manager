import { randomUUID } from "node:crypto";
import { z } from "zod";
import { prisma } from "../../db/prisma.ts";
import { ApiError } from "../../shared/errors.ts";
import { parseWith } from "../../shared/validation.ts";
import { requireSiteAccess, requireTaskAccess } from "../../shared/authz.ts";
import { parseDateOnly, todayInCairo } from "../../shared/dates.ts";
import { serializeSite, serializeTask, serializeVisit } from "../../shared/serializers.ts";

export const TOOL_NAMES = [
  "searchSites",
  "getSiteSummary",
  "listOpenTasks",
  "getVisitHistory",
  "prepareVisitDraft",
  "prepareTaskDraft",
  "prepareTaskUpdate",
] as const;

export type ToolName = (typeof TOOL_NAMES)[number];

const uuid = z.uuid();
const dateOnly = z
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

const argsSchemas = {
  searchSites: z.object({
    query: z.string().trim().max(120).optional(),
    limit: z.coerce.number().int().min(1).max(20).default(8),
  }),
  getSiteSummary: z.object({ siteId: uuid }),
  listOpenTasks: z.object({
    siteId: uuid.optional(),
    limit: z.coerce.number().int().min(1).max(50).default(20),
  }),
  getVisitHistory: z.object({
    siteId: uuid,
    from: dateOnly.optional(),
    to: dateOnly.optional(),
    limit: z.coerce.number().int().min(1).max(50).default(15),
  }),
  prepareVisitDraft: z.object({
    siteId: uuid,
    visitDate: dateOnly.optional(),
    completedWork: z.string().trim().min(1).max(5000),
    remainingWork: optionalText(5000),
    notes: optionalText(5000),
  }),
  prepareTaskDraft: z.object({
    siteId: uuid.optional(),
    title: z.string().trim().min(1).max(200),
    description: optionalText(2000),
    priority: z.enum(["LOW", "NORMAL", "HIGH"]).default("NORMAL"),
    dueDate: dateOnly.nullable().optional(),
  }),
  prepareTaskUpdate: z.object({
    taskId: uuid,
    status: z.enum(["OPEN", "IN_PROGRESS", "DONE"]).optional(),
    title: z.string().trim().min(1).max(200).optional(),
    description: optionalText(2000),
    priority: z.enum(["LOW", "NORMAL", "HIGH"]).optional(),
    dueDate: dateOnly.nullable().optional(),
  }),
} satisfies Record<ToolName, z.ZodType>;

async function accessibleWorkspaceIds(userId: string): Promise<string[]> {
  const memberships = await prisma.workspaceMember.findMany({
    where: { userId },
    select: { workspaceId: true },
  });
  return memberships.map((membership) => membership.workspaceId);
}

function siteAccessFilter(userId: string, workspaceIds: string[]) {
  return [
    { scope: "PERSONAL" as const, ownerUserId: userId },
    { scope: "COMPANY" as const, workspaceId: { in: workspaceIds } },
  ];
}

async function searchSites(userId: string, args: z.infer<typeof argsSchemas.searchSites>) {
  const workspaceIds = await accessibleWorkspaceIds(userId);
  const sites = await prisma.site.findMany({
    where: {
      AND: [
        { OR: siteAccessFilter(userId, workspaceIds) },
        args.query
          ? {
              OR: [
                { name: { contains: args.query, mode: "insensitive" } },
                { address: { contains: args.query, mode: "insensitive" } },
              ],
            }
          : {},
      ],
    },
    include: {
      _count: { select: { tasks: { where: { status: { not: "DONE" } } } } },
      visits: { orderBy: [{ visitDate: "desc" }, { createdAt: "desc" }], take: 1 },
    },
    orderBy: { updatedAt: "desc" },
    take: args.limit,
  });

  return {
    sites: sites.map((site) => ({
      id: site.id,
      name: site.name,
      scope: site.scope,
      address: site.address,
      openTaskCount: site._count.tasks,
      lastVisitDate: site.visits[0] ? serializeVisit(site.visits[0]).visitDate : null,
    })),
    note: sites.length === 0 ? "مفيش مواقع مطابقة في البيانات المسموح لك بها." : undefined,
  };
}

async function getSiteSummary(userId: string, args: z.infer<typeof argsSchemas.getSiteSummary>) {
  const access = await requireSiteAccess(userId, args.siteId, "read");
  const site = await prisma.site.findUnique({
    where: { id: args.siteId },
    include: {
      workspace: { select: { id: true, name: true } },
      tasks: {
        where: { status: { not: "DONE" } },
        orderBy: [{ priority: "desc" }, { createdAt: "desc" }],
        take: 30,
        include: { assignee: { select: { id: true, name: true } } },
      },
      visits: {
        orderBy: [{ visitDate: "desc" }, { createdAt: "desc" }],
        take: 5,
        include: { createdBy: { select: { id: true, name: true } } },
      },
      _count: { select: { tasks: { where: { status: { not: "DONE" } } } } },
    },
  });
  if (!site) throw ApiError.notFound("Site not found");

  return {
    site: serializeSite(site),
    canWrite: access.canWrite,
    openTasks: site.tasks.map(serializeTask),
    recentVisits: site.visits.map(serializeVisit),
    openTaskCount: site._count.tasks,
  };
}

async function listOpenTasks(userId: string, args: z.infer<typeof argsSchemas.listOpenTasks>) {
  if (args.siteId) await requireSiteAccess(userId, args.siteId, "read");

  const workspaceIds = await accessibleWorkspaceIds(userId);
  const tasks = await prisma.task.findMany({
    where: {
      status: { not: "DONE" },
      ...(args.siteId
        ? { siteId: args.siteId }
        : {
            OR: [
              { site: { is: { OR: siteAccessFilter(userId, workspaceIds) } } },
              { siteId: null, OR: [{ createdById: userId }, { assigneeId: userId }] },
            ],
          }),
    },
    include: {
      site: { select: { id: true, name: true, scope: true } },
      assignee: { select: { id: true, name: true } },
    },
    orderBy: [{ priority: "desc" }, { dueDate: { sort: "asc", nulls: "last" } }],
    take: args.limit,
  });

  return { tasks: tasks.map(serializeTask), count: tasks.length };
}

async function getVisitHistory(userId: string, args: z.infer<typeof argsSchemas.getVisitHistory>) {
  await requireSiteAccess(userId, args.siteId, "read");
  const visits = await prisma.visit.findMany({
    where: {
      siteId: args.siteId,
      ...(args.from || args.to
        ? {
            visitDate: {
              ...(args.from ? { gte: parseDateOnly(args.from) } : {}),
              ...(args.to ? { lte: parseDateOnly(args.to) } : {}),
            },
          }
        : {}),
    },
    include: { createdBy: { select: { id: true, name: true } } },
    orderBy: [{ visitDate: "desc" }, { createdAt: "desc" }],
    take: args.limit,
  });
  return { visits: visits.map(serializeVisit), count: visits.length };
}

async function prepareVisitDraft(
  userId: string,
  args: z.infer<typeof argsSchemas.prepareVisitDraft>,
) {
  const access = await requireSiteAccess(userId, args.siteId, "write");
  const visitDate = args.visitDate ?? todayInCairo();

  const openTasks = await prisma.task.findMany({
    where: { siteId: args.siteId, status: { not: "DONE" } },
    orderBy: [{ priority: "desc" }, { createdAt: "desc" }],
    take: 30,
  });

  return {
    kind: "visit",
    requiresConfirmation: true,
    operationId: randomUUID(),
    site: { id: access.site.id, name: access.site.name },
    visitDate,
    completedWork: args.completedWork,
    remainingWork: args.remainingWork ?? null,
    notes: args.notes ?? null,
    openTasksAtDraftTime: openTasks.map((task) => ({
      id: task.id,
      title: task.title,
      status: task.status,
      priority: task.priority,
    })),
    warning:
      openTasks.length > 0
        ? "في مهام مفتوحة حالياً. تغييرها لازم يتأكد لوحده ومش بيعدل الزيارة القديمة."
        : null,
  };
}

async function prepareTaskDraft(
  userId: string,
  args: z.infer<typeof argsSchemas.prepareTaskDraft>,
) {
  let siteName: string | null = null;
  if (args.siteId) {
    const access = await requireSiteAccess(userId, args.siteId, "write");
    siteName = access.site.name;
  }

  return {
    kind: "task",
    requiresConfirmation: true,
    operationId: randomUUID(),
    site: args.siteId ? { id: args.siteId, name: siteName } : null,
    title: args.title,
    description: args.description ?? null,
    priority: args.priority,
    dueDate: args.dueDate ?? null,
    status: "OPEN",
  };
}

async function prepareTaskUpdate(
  userId: string,
  args: z.infer<typeof argsSchemas.prepareTaskUpdate>,
) {
  const { task } = await requireTaskAccess(userId, args.taskId, "write");

  const proposed = {
    ...(args.status !== undefined ? { status: args.status } : {}),
    ...(args.title !== undefined ? { title: args.title } : {}),
    ...(args.description !== undefined ? { description: args.description } : {}),
    ...(args.priority !== undefined ? { priority: args.priority } : {}),
    ...(args.dueDate !== undefined ? { dueDate: args.dueDate } : {}),
  };

  if (Object.keys(proposed).length === 0) {
    throw ApiError.badRequest("The assistant did not propose any task changes");
  }

  return {
    kind: "taskUpdate",
    requiresConfirmation: true,
    taskId: task.id,
    baseUpdatedAt: task.updatedAt.toISOString(),
    siteId: task.siteId,
    before: {
      title: task.title,
      status: task.status,
      priority: task.priority,
      dueDate: task.dueDate ? serializeTask(task).dueDate : null,
    },
    proposed,
  };
}

export async function executeTool(
  userId: string,
  name: string,
  rawArgs: unknown,
): Promise<Record<string, unknown>> {
  if (!TOOL_NAMES.includes(name as ToolName)) {
    throw ApiError.badRequest(`Unknown assistant action: ${name}`);
  }
  const tool = name as ToolName;
  const args = parseWith(argsSchemas[tool], rawArgs ?? {}) as never;

  switch (tool) {
    case "searchSites":
      return { ok: true, result: await searchSites(userId, args) };
    case "getSiteSummary":
      return { ok: true, result: await getSiteSummary(userId, args) };
    case "listOpenTasks":
      return { ok: true, result: await listOpenTasks(userId, args) };
    case "getVisitHistory":
      return { ok: true, result: await getVisitHistory(userId, args) };
    case "prepareVisitDraft":
      return { ok: true, result: await prepareVisitDraft(userId, args) };
    case "prepareTaskDraft":
      return { ok: true, result: await prepareTaskDraft(userId, args) };
    case "prepareTaskUpdate":
      return { ok: true, result: await prepareTaskUpdate(userId, args) };
    default:
      throw ApiError.badRequest("Unknown assistant action");
  }
}

export async function buildAssistantContext(userId: string): Promise<string> {
  const workspaceIds = await accessibleWorkspaceIds(userId);
  const sites = await prisma.site.findMany({
    where: { OR: siteAccessFilter(userId, workspaceIds) },
    include: { _count: { select: { tasks: { where: { status: { not: "DONE" } } } } } },
    orderBy: { updatedAt: "desc" },
    take: 40,
  });

  const lines = sites.map(
    (site) =>
      `- ${site.name} (id: ${site.id}) — ${site.address} — مهام مفتوحة: ${site._count.tasks} — ${site.scope === "COMPANY" ? "موقع شركة" : "شغل شخصي"}`,
  );

  return [
    `تاريخ اليوم في القاهرة: ${todayInCairo()}`,
    "المواقع المسموح بها:",
    ...(lines.length > 0 ? lines : ["- لا توجد مواقع محفوظة بعد."]),
  ].join("\n");
}
