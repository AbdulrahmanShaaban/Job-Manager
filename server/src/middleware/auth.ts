import type { RequestHandler } from "express";
import { prisma } from "../db/prisma.ts";
import { hashSessionToken } from "../shared/tokens.ts";
import { ApiError } from "../shared/errors.ts";

export interface AuthContext {
  userId: string;
  sessionId: string;
  user: {
    id: string;
    name: string;
    email: string;
  };
}

declare global {
  namespace Express {
    interface Request {
      auth?: AuthContext;
    }
  }
}

export const requireAuth: RequestHandler = async (req, _res, next) => {
  try {
    const header = req.header("authorization");
    if (!header?.startsWith("Bearer ")) {
      throw ApiError.unauthorized();
    }

    const token = header.slice("Bearer ".length).trim();
    if (!token) throw ApiError.unauthorized();

    const session = await prisma.session.findUnique({
      where: { tokenHash: hashSessionToken(token) },
      include: { user: { select: { id: true, name: true, email: true } } },
    });

    if (!session || session.revokedAt || session.expiresAt.getTime() <= Date.now()) {
      throw ApiError.unauthorized("Your session has expired. Please sign in again.");
    }

    req.auth = {
      userId: session.userId,
      sessionId: session.id,
      user: session.user,
    };
    next();
  } catch (error) {
    next(error);
  }
};

export function authOf(req: Express.Request): AuthContext {
  if (!req.auth) throw ApiError.unauthorized();
  return req.auth;
}
