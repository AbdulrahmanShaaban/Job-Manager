import "dotenv/config";
import { defineConfig } from "prisma/config";

// CLI-only database access (migrations, generate). Runtime uses DATABASE_URL
// (pooled Neon endpoint) through @prisma/adapter-neon in src/db/prisma.ts.
// The placeholder keeps `prisma generate` working in offline CI where no
// database is reachable; it is never used to connect unless explicitly run.
const directUrl =
  process.env.DIRECT_URL ??
  process.env.DATABASE_URL ??
  "postgresql://job_manager:job_manager@localhost:5432/job_manager";

export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: {
    path: "prisma/migrations",
    seed: "tsx prisma/seed.ts",
  },
  datasource: {
    url: directUrl,
  },
});
