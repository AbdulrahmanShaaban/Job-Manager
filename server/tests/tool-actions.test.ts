import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  memberFindMany: vi.fn(),
  memberFindUnique: vi.fn(),
  siteFindMany: vi.fn(),
  siteFindUnique: vi.fn(),
  taskFindMany: vi.fn(),
  visitFindMany: vi.fn(),
  taskCreate: vi.fn(),
  visitCreate: vi.fn(),
}));

vi.mock("../src/db/prisma.ts", () => ({
  prisma: {
    workspaceMember: { findMany: mocks.memberFindMany, findUnique: mocks.memberFindUnique },
    site: { findMany: mocks.siteFindMany, findUnique: mocks.siteFindUnique },
    task: { findMany: mocks.taskFindMany, create: mocks.taskCreate },
    visit: { findMany: mocks.visitFindMany, create: mocks.visitCreate },
  },
}));

const { executeTool } = await import("../src/modules/voice/tool-actions.ts");

describe("assistant tool actions", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.memberFindMany.mockResolvedValue([{ workspaceId: "ws-1" }]);
  });

  it("rejects unknown tools", async () => {
    await expect(executeTool("user-1", "dropDatabase", {})).rejects.toMatchObject({
      status: 400,
    });
  });

  it("validates tool arguments", async () => {
    await expect(executeTool("user-1", "getSiteSummary", {})).rejects.toMatchObject({
      status: 422,
    });
  });

  it("searches only authorized sites and returns real open-task counts", async () => {
    mocks.siteFindMany.mockResolvedValue([
      {
        id: "site-1",
        name: "قرنفل",
        scope: "PERSONAL",
        address: "المعادي",
        _count: { tasks: 3 },
        visits: [],
      },
    ]);

    const result = (await executeTool("user-1", "searchSites", { query: "قرنفل" })) as {
      ok: boolean;
      result: { sites: Array<{ name: string; openTaskCount: number }> };
    };

    expect(result.ok).toBe(true);
    expect(result.result.sites[0]?.openTaskCount).toBe(3);
    expect(mocks.siteFindMany).toHaveBeenCalledTimes(1);
    const where = mocks.siteFindMany.mock.calls[0]?.[0]?.where;
    expect(JSON.stringify(where)).toContain("user-1");
    expect(JSON.stringify(where)).toContain("ws-1");
  });

  it("prepares a visit draft without writing anything", async () => {
    mocks.siteFindUnique.mockResolvedValue({
      id: "site-1",
      name: "مصنع صدره",
      scope: "PERSONAL",
      ownerUserId: "user-1",
      workspaceId: null,
    });
    mocks.taskFindMany.mockResolvedValue([]);

    const result = (await executeTool("user-1", "prepareVisitDraft", {
      siteId: "6a1f8f3e-8f0f-4a5e-9b0a-1d2c3b4a5e6f",
      completedWork: "تركيب كاميرتين",
      remainingWork: "تلاتة كاميرات",
    })) as {
      ok: boolean;
      result: { kind: string; requiresConfirmation: boolean; operationId: string; openTasksAtDraftTime: unknown[] };
    };

    expect(result.result.kind).toBe("visit");
    expect(result.result.requiresConfirmation).toBe(true);
    expect(result.result.operationId).toMatch(/^[0-9a-f-]{36}$/);
    expect(mocks.visitCreate).not.toHaveBeenCalled();
    expect(mocks.taskCreate).not.toHaveBeenCalled();
  });

  it("blocks a viewer from preparing a write draft", async () => {
    mocks.siteFindUnique.mockResolvedValue({
      id: "site-2",
      name: "موقع شركة",
      scope: "COMPANY",
      ownerUserId: null,
      workspaceId: "ws-1",
    });
    mocks.memberFindUnique.mockResolvedValue({ role: "VIEWER" });

    await expect(
      executeTool("user-1", "prepareVisitDraft", {
        siteId: "6a1f8f3e-8f0f-4a5e-9b0a-1d2c3b4a5e6f",
        completedWork: "شغل",
      }),
    ).rejects.toMatchObject({ status: 403 });
  });
});
