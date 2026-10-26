import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import { env } from "../config/env.ts";

/**
 * Session and invitation tokens are opaque 256-bit/192-bit random strings.
 * Only an HMAC-SHA256 digest is stored, keyed by AUTH_SECRET, so a leaked
 * database dump cannot be replayed as a bearer token and cannot be brute
 * forced offline without also leaking the server secret.
 *
 * Rotating AUTH_SECRET invalidates every existing session and pending
 * invitation. That is intentional: it is the emergency "sign everyone out"
 * lever.
 */
export function hashSessionToken(token: string): string {
  return createHmac("sha256", env.authSecret).update(token).digest("hex");
}

export function createSessionToken(): string {
  return randomBytes(32).toString("base64url");
}

export function createInvitationToken(): string {
  return randomBytes(24).toString("base64url");
}

export function safeEqual(a: string, b: string): boolean {
  const bufferA = Buffer.from(a);
  const bufferB = Buffer.from(b);
  if (bufferA.length !== bufferB.length) return false;
  return timingSafeEqual(bufferA, bufferB);
}
