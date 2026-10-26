import { PrismaNeon } from "@prisma/adapter-neon";
import { PrismaClient } from "../generated/prisma/client.ts";
import { env } from "../config/env.ts";

const adapter = new PrismaNeon({ connectionString: env.databaseUrl });

export const prisma = new PrismaClient({ adapter });

export async function disconnectPrisma(): Promise<void> {
  await prisma.$disconnect();
}
