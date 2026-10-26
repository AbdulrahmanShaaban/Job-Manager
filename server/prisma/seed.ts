import argon2 from "argon2";
import { prisma } from "../src/db/prisma.ts";
import { env } from "../src/config/env.ts";

async function main(): Promise<void> {
  const email = env.SEED_OWNER_EMAIL.trim().toLowerCase();
  const password = env.SEED_OWNER_PASSWORD;

  if (!password || password.length < 8) {
    throw new Error(
      "Set SEED_OWNER_PASSWORD (at least 8 characters) before running the seed script.",
    );
  }

  const existingUser = await prisma.user.findUnique({ where: { email } });
  const user =
    existingUser ??
    (await prisma.user.create({
      data: {
        name: env.SEED_OWNER_NAME,
        email,
        passwordHash: await argon2.hash(password, { type: argon2.argon2id }),
      },
    }));

  let workspace = await prisma.workspace.findFirst({
    where: { name: env.SEED_WORKSPACE_NAME },
  });
  workspace ??= await prisma.workspace.create({ data: { name: env.SEED_WORKSPACE_NAME } });

  await prisma.workspaceMember.upsert({
    where: { workspaceId_userId: { workspaceId: workspace.id, userId: user.id } },
    create: { workspaceId: workspace.id, userId: user.id, role: "OWNER" },
    update: { role: "OWNER" },
  });

  console.log(`Owner ready: ${email}`);
  console.log(`Workspace ready: ${workspace.name} (${workspace.id})`);
  console.log(existingUser ? "Existing user kept; password unchanged." : "New user created.");
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
