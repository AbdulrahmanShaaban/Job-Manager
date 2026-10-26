import type { Site, Task, Visit } from "../generated/prisma/client.ts";
import { formatDateOnly } from "./dates.ts";

type SiteLike = Site & {
  workspace?: { id: string; name: string } | null;
  visits?: Visit[];
  _count?: { tasks: number };
};

type VisitLike = Visit & {
  createdBy?: { id: string; name: string } | null;
};

type TaskLike = Task & {
  site?: { id: string; name: string; scope: string } | null;
  assignee?: { id: string; name: string } | null;
};

export function serializeSite(site: SiteLike) {
  return {
    id: site.id,
    name: site.name,
    scope: site.scope,
    status: site.status,
    ownerUserId: site.ownerUserId,
    workspaceId: site.workspaceId,
    workspace: site.workspace ? { id: site.workspace.id, name: site.workspace.name } : null,
    address: site.address,
    contactName: site.contactName,
    contactPhone: site.contactPhone,
    mapUrl: site.mapUrl,
    latitude: site.latitude,
    longitude: site.longitude,
    generalNotes: site.generalNotes,
    openTaskCount: site._count?.tasks ?? 0,
    lastVisit: site.visits?.[0] ? serializeVisit(site.visits[0]) : null,
    createdAt: site.createdAt.toISOString(),
    updatedAt: site.updatedAt.toISOString(),
  };
}

export function serializeVisit(visit: VisitLike) {
  return {
    id: visit.id,
    siteId: visit.siteId,
    visitDate: formatDateOnly(visit.visitDate),
    completedWork: visit.completedWork,
    remainingWork: visit.remainingWork,
    notes: visit.notes,
    transcript: visit.transcript,
    source: visit.source,
    createdById: visit.createdById,
    createdBy: visit.createdBy ? { id: visit.createdBy.id, name: visit.createdBy.name } : null,
    revision: visit.revision,
    editedAt: visit.editedAt?.toISOString() ?? null,
    createdAt: visit.createdAt.toISOString(),
    updatedAt: visit.updatedAt.toISOString(),
  };
}

export function serializeTask(task: TaskLike) {
  return {
    id: task.id,
    siteId: task.siteId,
    site: task.site ?? null,
    title: task.title,
    description: task.description,
    status: task.status,
    priority: task.priority,
    dueDate: task.dueDate ? formatDateOnly(task.dueDate) : null,
    completedAt: task.completedAt?.toISOString() ?? null,
    createdById: task.createdById,
    assigneeId: task.assigneeId,
    assignee: task.assignee ? { id: task.assignee.id, name: task.assignee.name } : null,
    createdAt: task.createdAt.toISOString(),
    updatedAt: task.updatedAt.toISOString(),
  };
}
