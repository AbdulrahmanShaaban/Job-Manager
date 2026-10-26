import argon2 from "argon2";
import { Router } from "express";
import { z } from "zod";
import { prisma } from "../../db/prisma.ts";
import { env } from "../../config/env.ts";
import { ApiError } from "../../shared/errors.ts";
import { parseWith } from "../../shared/validation.ts";
import { createSessionToken, hashSessionToken } from "../../shared/tokens.ts";
import { requireAuth, authOf } from "../../middleware/auth.ts";
import { authRateLimit } from "../../middleware/rate-limit.ts";

export const authRouter = Router();

const emailSchema = z.email().max(254);
const passwordSchema = z.string().min(8).max(200);

const loginSchema = z.object({
  email: emailSchema,
  password: z.string().min(1).max(200),
});

const acceptInvitationSchema = z.object({
  token: z.string().min(10).max(200),
  name: z.string().trim().min(1).max(120),
  password: passwordSchema,
});

// A valid Argon2id hash used to keep failed-login timing similar whether or not
// the email exists. Generated once, lazily, and never used as a real password.
let dummyHashPromise: Promise<string> | undefined;
function dummyHash(): Promise<string> {
  dummyHashPromise ??= argon2.hash("not-a-real-user-password", { type: argon2.argon2id });
  return dummyHashPromise;
}

export async function createSession(userId: string, userAgent?: string) {
  const token = createSessionToken();
  const expiresAt = new Date(Date.now() + env.SESSION_TTL_DAYS * 24 * 60 * 60 * 1000);
  const session = await prisma.session.create({
    data: {
      userId,
      tokenHash: hashSessionToken(token),
      expiresAt,
      userAgent: userAgent?.slice(0, 300),
    },
  });
  return { token, expiresAt, sessionId: session.id };
}

async function workspacesFor(userId: string) {
  const memberships = await prisma.workspaceMember.findMany({
    where: { userId },
    include: { workspace: { select: { id: true, name: true } } },
    orderBy: { createdAt: "asc" },
  });
  return memberships.map((membership) => ({
    id: membership.workspace.id,
    name: membership.workspace.name,
    role: membership.role,
  }));
}

authRouter.post("/login", authRateLimit, async (req, res) => {
  const body = parseWith(loginSchema, req.body);
  const email = body.email.trim().toLowerCase();

  const user = await prisma.user.findUnique({ where: { email } });
  if (!user) {
    await argon2.verify(await dummyHash(), body.password);
    throw ApiError.unauthorized("Invalid email or password");
  }

  const valid = await argon2.verify(user.passwordHash, body.password);
  if (!valid) throw ApiError.unauthorized("Invalid email or password");

  const session = await createSession(user.id, req.header("user-agent"));

  res.json({
    token: session.token,
    expiresAt: session.expiresAt.toISOString(),
    user: { id: user.id, name: user.name, email: user.email },
    workspaces: await workspacesFor(user.id),
  });
});

authRouter.post("/accept-invitation", authRateLimit, async (req, res) => {
  const body = parseWith(acceptInvitationSchema, req.body);

  const invitation = await prisma.invitation.findUnique({
    where: { tokenHash: hashSessionToken(body.token) },
    include: { workspace: { select: { id: true, name: true } } },
  });

  if (!invitation || invitation.acceptedAt || invitation.expiresAt.getTime() <= Date.now()) {
    throw ApiError.badRequest("This invitation is invalid or has expired");
  }

  const email = invitation.email.toLowerCase();
  const existing = await prisma.user.findUnique({ where: { email } });
  if (existing) {
    throw ApiError.conflict("An account with this email already exists. Sign in instead.");
  }

  const passwordHash = await argon2.hash(body.password, { type: argon2.argon2id });

  const user = await prisma.$transaction(async (tx) => {
    const created = await tx.user.create({
      data: { name: body.name.trim(), email, passwordHash },
    });

    await tx.workspaceMember.create({
      data: { workspaceId: invitation.workspaceId, userId: created.id, role: invitation.role },
    });

    await tx.invitation.update({
      where: { id: invitation.id },
      data: { acceptedAt: new Date() },
    });

    return created;
  });

  const session = await createSession(user.id, req.header("user-agent"));

  res.status(201).json({
    token: session.token,
    expiresAt: session.expiresAt.toISOString(),
    user: { id: user.id, name: user.name, email: user.email },
    workspaces: await workspacesFor(user.id),
  });
});

authRouter.post("/logout", requireAuth, async (req, res) => {
  const auth = authOf(req);
  await prisma.session.update({
    where: { id: auth.sessionId },
    data: { revokedAt: new Date() },
  });
  res.status(204).end();
});

authRouter.get("/me", requireAuth, async (req, res) => {
  const auth = authOf(req);
  res.json({
    user: auth.user,
    workspaces: await workspacesFor(auth.userId),
  });
});
