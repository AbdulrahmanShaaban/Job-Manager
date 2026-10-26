import { createApp } from "../server/src/app.ts";

// Vercel serverless entry point. Exports the Express app; Vercel handles
// listening. Prisma uses the Neon adapter (serverless-friendly) and reads
// DATABASE_URL / DIRECT_URL / AUTH_SECRET from the Vercel environment.
const app = createApp();
export default app;
