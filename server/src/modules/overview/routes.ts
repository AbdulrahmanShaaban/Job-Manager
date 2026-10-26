import { Router } from "express";
import { prisma } from "../../db/prisma.ts";
import { requireAuth, authOf } from "../../middleware/auth.ts";
import { parseDateOnly, todayInCairo } from "../../shared/dates.ts";
import { serializeSite, serializeTask, serializeVisit } from "../../shared/serializers.ts";

export const overviewRouter = Router();
overviewRouter.use(requireAuth);

overviewRouter.get("/", async (req, res) => {
  const auth = authOf(req);
  const today = todayInCairo();

  const memberships = await prisma.workspaceMember.findMany({
    where: { userId: auth.userId },
    select: { workspaceId: true, role: true, workspace: { select: { id: true, name: true } } },
  });
  const workspaceIds = memberships.map((membership) => membership.workspaceId);

  const siteAccessOr = [
    { scope: "PERSONAL" as const, ownerUserId: auth.userId },
    { scope: "COMPANY" as const, workspaceId: { in: workspaceIds } },
  ];

  const [personalSites, companySites, todayVisits, openTasks, recentSites, upcomingTasks] =
    await Promise.all([
      prisma.site.count({ where: { scope: "PERSONAL", ownerUserId: auth.userId } }),
      prisma.site.count({ where: { scope: "COMPANY", workspaceId: { in: workspaceIds } } }),
      prisma.visit.count({
        where: { visitDate: parseDateOnly(today), site: { is: { OR: siteAccessOr } } },
      }),
      prisma.task.count({
        where: {
          status: { not: "DONE" },
          OR: [
            { site: { is: { OR: siteAccessOr } } },
            { siteId: null, OR: [{ createdById: auth.userId }, { assigneeId: auth.userId }] },
          ],
        },
      }),
      prisma.site.findMany({
        where: { OR: siteAccessOr },
        include: {
          workspace: { select: { id: true, name: true } },
          visits: {
            orderBy: [{ visitDate: "desc" }, { createdAt: "desc" }],
            take: 1,
          },
          _count: { select: { tasks: { where: { status: { not: "DONE" } } } } },
        },
        orderBy: { updatedAt: "desc" },
        take: 6,
      }),
      prisma.task.findMany({
        where: {
          status: { not: "DONE" },
          OR: [
            { site: { is: { OR: siteAccessOr } } },
            { siteId: null, OR: [{ createdById: auth.userId }, { assigneeId: auth.userId }] },
          ],
        },
        include: {
          site: { select: { id: true, name: true, scope: true } },
          assignee: { select: { id: true, name: true } },
        },
        orderBy: [
          { priority: "desc" },
          { dueDate: { sort: "asc", nulls: "last" } },
          { createdAt: "desc" },
        ],
        take: 8,
      }),
    ]);

  const todayVisitRows = await prisma.visit.findMany({
    where: { visitDate: parseDateOnly(today), site: { is: { OR: siteAccessOr } } },
    include: {
      createdBy: { select: { id: true, name: true } },
      site: { select: { id: true, name: true, scope: true } },
    },
    orderBy: { createdAt: "desc" },
    take: 10,
  });

  res.json({
    overview: {
      today,
      counts: {
        personalSites,
        companySites,
        todayVisits,
        openTasks,
      },
      recentSites: recentSites.map(serializeSite),
      todayVisits: todayVisitRows.map((visit) => ({
        ...serializeVisit(visit),
        site: visit.site,
      })),
      upcomingTasks: upcomingTasks.map(serializeTask),
      workspaces: memberships.map((membership) => ({
        id: membership.workspace.id,
        name: membership.workspace.name,
        role: membership.role,
      })),
    },
  });
});
