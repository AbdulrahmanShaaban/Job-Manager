import { Router } from "express";
import { z } from "zod";
import { prisma } from "../../db/prisma.ts";
import { parseWith } from "../../shared/validation.ts";
import { requireAuth, authOf } from "../../middleware/auth.ts";
import { serializeSite, serializeTask, serializeVisit } from "../../shared/serializers.ts";

export const exportRouter = Router();
exportRouter.use(requireAuth);

// Export is intentionally unpaginated for small field datasets, but every query
// is bounded so one large account cannot exhaust server memory. When a bound is
// hit the response carries `x-export-truncated: true`.
const MAX_EXPORT_SITES = 1000;
const MAX_VISITS_PER_SITE = 100;
const MAX_TASKS_PER_SITE = 100;
const MAX_PERSONAL_TASKS = 1000;

function csvCell(value: unknown): string {
  if (value === null || value === undefined) return "";
  let text = value instanceof Date ? value.toISOString() : String(value);
  // CSV formula injection: a cell that starts with = + - @ TAB or CR is
  // evaluated as a formula by Excel/LibreOffice. This file is explicitly
  // produced for Excel (UTF-8 BOM below), so neutralise it with a leading
  // apostrophe, which those apps treat as "literal text".
  if (/^[=+\-@\t\r]/.test(text)) text = `'${text}`;
  if (/[",\r\n]/.test(text)) return `"${text.replace(/"/g, '""')}"`;
  return text;
}

function toCsv(headers: string[], rows: unknown[][]): string {
  const lines = [headers.map(csvCell).join(","), ...rows.map((row) => row.map(csvCell).join(","))];
  // BOM keeps Arabic readable when opened in Excel.
  return `\uFEFF${lines.join("\r\n")}\r\n`;
}

exportRouter.get("/", async (req, res) => {
  const auth = authOf(req);
  const query = parseWith(
    z.object({
      format: z.enum(["json", "csv"]).default("json"),
      entity: z.enum(["sites", "visits", "tasks"]).optional(),
    }),
    req.query,
  );

  const memberships = await prisma.workspaceMember.findMany({
    where: { userId: auth.userId },
    include: { workspace: { select: { id: true, name: true } } },
  });
  const workspaceIds = memberships.map((membership) => membership.workspaceId);

  const sites = await prisma.site.findMany({
    where: {
      OR: [
        { scope: "PERSONAL", ownerUserId: auth.userId },
        { scope: "COMPANY", workspaceId: { in: workspaceIds } },
      ],
    },
    include: {
      workspace: { select: { id: true, name: true } },
      visits: {
        orderBy: [{ visitDate: "desc" }, { createdAt: "desc" }],
        take: MAX_VISITS_PER_SITE,
        include: { createdBy: { select: { id: true, name: true } } },
      },
      tasks: {
        take: MAX_TASKS_PER_SITE,
        include: {
          site: { select: { id: true, name: true, scope: true } },
          assignee: { select: { id: true, name: true } },
        },
        orderBy: { createdAt: "desc" },
      },
    },
    orderBy: { updatedAt: "desc" },
    take: MAX_EXPORT_SITES,
  });

  const personalTasks = await prisma.task.findMany({
    where: {
      siteId: null,
      OR: [{ createdById: auth.userId }, { assigneeId: auth.userId }],
    },
    include: {
      site: { select: { id: true, name: true, scope: true } },
      assignee: { select: { id: true, name: true } },
    },
    take: MAX_PERSONAL_TASKS,
  });

  const truncated =
    sites.length >= MAX_EXPORT_SITES ||
    personalTasks.length >= MAX_PERSONAL_TASKS ||
    sites.some(
      (site) =>
        site.visits.length >= MAX_VISITS_PER_SITE || site.tasks.length >= MAX_TASKS_PER_SITE,
    );

  if (truncated) {
    res.setHeader("x-export-truncated", "true");
  }

  if (query.format === "json") {
    res.setHeader("content-disposition", `attachment; filename="job-manager-export-${new Date().toISOString().slice(0, 10)}.json"`);
    res.json({
      exportedAt: new Date().toISOString(),
      user: auth.user,
      workspaces: memberships.map((membership) => ({
        id: membership.workspace.id,
        name: membership.workspace.name,
        role: membership.role,
      })),
      sites: sites.map((site) => ({
        ...serializeSite(site),
        visits: site.visits.map(serializeVisit),
        tasks: site.tasks.map(serializeTask),
      })),
      personalTasks: personalTasks.map(serializeTask),
    });
    return;
  }

  const entity = query.entity ?? "sites";
  res.setHeader("content-type", "text/csv; charset=utf-8");

  if (entity === "sites") {
    res.setHeader("content-disposition", 'attachment; filename="sites.csv"');
    res.send(
      toCsv(
        [
          "id",
          "name",
          "scope",
          "status",
          "workspace",
          "address",
          "contactName",
          "contactPhone",
          "mapUrl",
          "latitude",
          "longitude",
          "generalNotes",
          "updatedAt",
        ],
        sites.map((site) => [
          site.id,
          site.name,
          site.scope,
          site.status,
          site.workspace?.name ?? "",
          site.address,
          site.contactName,
          site.contactPhone,
          site.mapUrl,
          site.latitude,
          site.longitude,
          site.generalNotes,
          site.updatedAt,
        ]),
      ),
    );
    return;
  }

  if (entity === "visits") {
    res.setHeader("content-disposition", 'attachment; filename="visits.csv"');
    res.send(
      toCsv(
        [
          "id",
          "siteId",
          "siteName",
          "visitDate",
          "completedWork",
          "remainingWork",
          "notes",
          "source",
          "createdBy",
          "createdAt",
        ],
        sites.flatMap((site) =>
          site.visits.map((visit) => [
            visit.id,
            site.id,
            site.name,
            visit.visitDate,
            visit.completedWork,
            visit.remainingWork,
            visit.notes,
            visit.source,
            visit.createdBy.name,
            visit.createdAt,
          ]),
        ),
      ),
    );
    return;
  }

  res.setHeader("content-disposition", 'attachment; filename="tasks.csv"');
  const allTasks = [...sites.flatMap((site) => site.tasks), ...personalTasks];
  res.send(
    toCsv(
      [
        "id",
        "siteId",
        "siteName",
        "title",
        "status",
        "priority",
        "dueDate",
        "assignee",
        "completedAt",
        "createdAt",
      ],
      allTasks.map((task) => [
        task.id,
        task.siteId,
        task.site?.name ?? "",
        task.title,
        task.status,
        task.priority,
        task.dueDate,
        task.assignee?.name ?? "",
        task.completedAt,
        task.createdAt,
      ]),
    ),
  );
});
