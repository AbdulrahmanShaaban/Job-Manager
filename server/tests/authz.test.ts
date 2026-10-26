import { beforeEach, describe, expect, it, vi } from "vitest";

const findUnique = vi.fn();

vi.mock("../src/db/prisma.ts", () => ({
  prisma: {
    workspaceMember: { findUnique },
  },
}));

const { getSiteAccess, roleSatisfies } = await import("../src/shared/authz.ts");

const personalSite = {
  id: "site-1",
  scope: "PERSONAL",
  ownerUserId: "user-1",
  workspaceId: null,
} as never;

const companySite = {
  id: "site-2",
  scope: "COMPANY",
  ownerUserId: null,
  workspaceId: "ws-1",
} as never;

describe("workspace authorization", () => {
  beforeEach(() => findUnique.mockReset());

  it("enforces the role ladder", () => {
    expect(roleSatisfies("VIEWER", "read")).toBe(true);
    expect(roleSatisfies("VIEWER", "write")).toBe(false);
    expect(roleSatisfies("EDITOR", "write")).toBe(true);
    expect(roleSatisfies("EDITOR", "manage")).toBe(false);
    expect(roleSatisfies("ADMIN", "manage")).toBe(true);
    expect(roleSatisfies("OWNER", "manage")).toBe(true);
  });

  it("keeps personal sites private to their owner", async () => {
    const owner = await getSiteAccess("user-1", personalSite);
    expect(owner.canRead).toBe(true);
    expect(owner.canWrite).toBe(true);

    const stranger = await getSiteAccess("user-2", personalSite);
    expect(stranger.canRead).toBe(false);
    expect(stranger.canWrite).toBe(false);
    expect(findUnique).not.toHaveBeenCalled();
  });

  it("requires workspace membership for company sites", async () => {
    findUnique.mockResolvedValue(null);
    const outsider = await getSiteAccess("user-2", companySite);
    expect(outsider.canRead).toBe(false);
  });

  it("maps viewer/editor/admin roles to read/write/manage", async () => {
    findUnique.mockResolvedValue({ role: "VIEWER" });
    const viewer = await getSiteAccess("user-1", companySite);
    expect(viewer.canRead).toBe(true);
    expect(viewer.canWrite).toBe(false);

    findUnique.mockResolvedValue({ role: "EDITOR" });
    const editor = await getSiteAccess("user-1", companySite);
    expect(editor.canWrite).toBe(true);
    expect(editor.canManage).toBe(false);

    findUnique.mockResolvedValue({ role: "ADMIN" });
    const admin = await getSiteAccess("user-1", companySite);
    expect(admin.canManage).toBe(true);
  });
});
