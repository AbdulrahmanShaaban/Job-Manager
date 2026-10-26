import type { Site, Task, WorkspaceRole } from "../generated/prisma/client.ts";
import { prisma } from "../db/prisma.ts";
import { ApiError } from "./errors.ts";

export type AccessLevel = "read" | "write" | "manage";

export const ROLE_RANK: Record<WorkspaceRole, number> = {
  VIEWER: 1,
  EDITOR: 2,
  ADMIN: 3,
  OWNER: 4,
};

const LEVEL_RANK: Record<AccessLevel, number> = {
  read: 1,
  write: 2,
  manage: 3,
};

export function roleSatisfies(role: WorkspaceRole, level: AccessLevel): boolean {
  return ROLE_RANK[role] >= LEVEL_RANK[level];
}

export interface SiteAccess {
  site: Site;
  workspaceRole: WorkspaceRole | null;
  canRead: boolean;
  canWrite: boolean;
  canManage: boolean;
}

function noAccess(site: Site): SiteAccess {
  return { site, workspaceRole: null, canRead: false, canWrite: false, canManage: false };
}

/**
 * Server-side source of truth for site visibility. Personal sites are private to
 * their owner; company sites require workspace membership. Never relies on AI.
 */
export async function getSiteAccess(userId: string, site: Site): Promise<SiteAccess> {
  if (site.scope === "PERSONAL") {
    if (site.ownerUserId !== userId) return noAccess(site);
    return { site, workspaceRole: null, canRead: true, canWrite: true, canManage: true };
  }

  if (!site.workspaceId) return noAccess(site);

  const membership = await prisma.workspaceMember.findUnique({
    where: { workspaceId_userId: { workspaceId: site.workspaceId, userId } },
  });

  if (!membership) return noAccess(site);

  return {
    site,
    workspaceRole: membership.role,
    canRead: true,
    canWrite: roleSatisfies(membership.role, "write"),
    canManage: roleSatisfies(membership.role, "manage"),
  };
}

export async function requireSiteAccess(
  userId: string,
  siteId: string,
  level: AccessLevel = "read",
): Promise<SiteAccess> {
  const site = await prisma.site.findUnique({ where: { id: siteId } });
  if (!site) throw ApiError.notFound("Site not found");

  const access = await getSiteAccess(userId, site);
  if (!access.canRead) {
    // Deliberately 404 so site IDs cannot be probed.
    throw ApiError.notFound("Site not found");
  }

  if (level === "write" && !access.canWrite) {
    throw ApiError.forbidden("Your workspace role does not allow editing this site");
  }
  if (level === "manage" && !access.canManage) {
    throw ApiError.forbidden("Only workspace owners or admins can do that");
  }

  return access;
}

export interface TaskAccess {
  task: Task;
  siteAccess: SiteAccess | null;
}

export async function requireTaskAccess(
  userId: string,
  taskId: string,
  level: AccessLevel = "read",
): Promise<TaskAccess> {
  const task = await prisma.task.findUnique({ where: { id: taskId } });
  if (!task) throw ApiError.notFound("Task not found");

  if (task.siteId) {
    const siteAccess = await requireSiteAccess(userId, task.siteId, level);
    return { task, siteAccess };
  }

  // A task not attached to a site is private to its creator and assignee.
  const isParticipant = task.createdById === userId || task.assigneeId === userId;
  if (!isParticipant) throw ApiError.notFound("Task not found");
  return { task, siteAccess: null };
}

export async function requireWorkspaceRole(
  userId: string,
  workspaceId: string,
  level: AccessLevel = "read",
): Promise<WorkspaceRole> {
  const membership = await prisma.workspaceMember.findUnique({
    where: { workspaceId_userId: { workspaceId, userId } },
  });
  if (!membership) throw ApiError.notFound("Workspace not found");
  if (!roleSatisfies(membership.role, level)) {
    throw ApiError.forbidden("Your workspace role does not allow that action");
  }
  return membership.role;
}

export function canWriteTask(userId: string, task: Task, siteAccess: SiteAccess | null): boolean {
  if (siteAccess) return siteAccess.canWrite;
  return task.createdById === userId || task.assigneeId === userId;
}
