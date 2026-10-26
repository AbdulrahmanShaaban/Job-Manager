import { Router } from "express";
import { z } from "zod";
import { prisma } from "../../db/prisma.ts";
import { ApiError } from "../../shared/errors.ts";
import { parseWith } from "../../shared/validation.ts";
import { requireAuth, authOf } from "../../middleware/auth.ts";
import { writeRateLimit } from "../../middleware/rate-limit.ts";
import { requireWorkspaceRole, roleSatisfies } from "../../shared/authz.ts";
import { createInvitationToken, hashSessionToken } from "../../shared/tokens.ts";

export const workspacesRouter = Router();
workspacesRouter.use(requireAuth);

const workspaceIdSchema = z.uuid();

const invitationSchema = z.object({
  email: z.email().max(254),
  role: z.enum(["ADMIN", "EDITOR", "VIEWER"]).default("EDITOR"),
});

workspacesRouter.get("/", async (req, res) => {
  const auth = authOf(req);
  const memberships = await prisma.workspaceMember.findMany({
    where: { userId: auth.userId },
    include: {
      workspace: {
        include: { _count: { select: { members: true, sites: true } } },
      },
    },
    orderBy: { createdAt: "asc" },
  });

  res.json({
    workspaces: memberships.map((membership) => ({
      id: membership.workspace.id,
      name: membership.workspace.name,
      role: membership.role,
      memberCount: membership.workspace._count.members,
      siteCount: membership.workspace._count.sites,
    })),
  });
});

workspacesRouter.get("/:id/members", async (req, res) => {
  const auth = authOf(req);
  const workspaceId = parseWith(workspaceIdSchema, req.params.id);
  const role = await requireWorkspaceRole(auth.userId, workspaceId, "read");
  // Email addresses are personal data. Only owners/admins (the people who
  // invite others) can see them; editors/viewers see names and roles only.
  const canSeeEmail = roleSatisfies(role, "manage");

  const members = await prisma.workspaceMember.findMany({
    where: { workspaceId },
    include: { user: { select: { id: true, name: true, email: true } } },
    orderBy: { createdAt: "asc" },
  });

  res.json({
    members: members.map((member) => ({
      id: member.user.id,
      name: member.user.name,
      email: canSeeEmail ? member.user.email : null,
      role: member.role,
    })),
  });
});

workspacesRouter.post("/:id/invitations", writeRateLimit, async (req, res) => {
  const auth = authOf(req);
  const workspaceId = parseWith(workspaceIdSchema, req.params.id);
  await requireWorkspaceRole(auth.userId, workspaceId, "manage");

  const body = parseWith(invitationSchema, req.body);
  const email = body.email.trim().toLowerCase();

  const existingUser = await prisma.user.findUnique({ where: { email } });
  if (existingUser) {
    throw ApiError.conflict("That person already has an account. Ask them to sign in.");
  }

  const token = createInvitationToken();
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

  const invitation = await prisma.invitation.create({
    data: {
      workspaceId,
      email,
      role: body.role,
      tokenHash: hashSessionToken(token),
      invitedById: auth.userId,
      expiresAt,
    },
  });

  // No email service is configured in this zero-cost build. The owner shares the
  // one-time code through an existing channel. Only the hash is stored.
  res.status(201).json({
    invitation: {
      id: invitation.id,
      email,
      role: invitation.role,
      expiresAt: expiresAt.toISOString(),
    },
    inviteCode: token,
    sharingNote: "Share this one-time code privately. It expires in 7 days.",
  });
});
