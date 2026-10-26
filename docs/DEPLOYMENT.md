# Deployment

This document describes how to deploy Job Manager from scratch. Nothing in this
document has been executed end-to-end: no Neon project, API host, or Android
signing key existed on the build machine. Treat every step as a checklist to run
and verify yourself, not as a report of completed work.

---

## 1. Topology

| Piece | Runs on | Notes |
| --- | --- | --- |
| PostgreSQL | Neon (managed) | Pooled URL for runtime, direct URL for migrations |
| API | Any Node 24 host with HTTPS | Single stateless process is enough |
| Mobile app | Android / iOS devices | Talks only to the API over HTTPS |

There is no Redis, no queue worker, no Docker requirement, and no second
service. One API process plus Neon is the whole backend.

---

## 2. Neon project

### 2.1 Create the project

1. Create a Neon project in the region closest to the API host.
2. Note the **pooled** connection string (host contains `-pooler`) and the
   **direct** connection string.
3. Keep `sslmode=require` on both.

### 2.2 Separate environments

Use two Neon branches (or two projects) at minimum:

| Environment | Purpose |
| --- | --- |
| `main` / production | Real client data. Migrations only after a backup. |
| `dev` | Schema experiments, restore drills, seed data |

A second branch in the **same** Neon project shares the project's storage and
compute quota. It is not an independent backup. See `DATABASE_BACKUP.md`.

### 2.3 Free-plan facts to re-verify before release

As checked on 26 October 2026, the Neon Free plan included roughly: 1 GB storage
per project, 100 CU-hours per project per month, 10 branches per project, one
manual snapshot, and Instant Restore history limited to 6 hours / 1 GB of change
history. Quotas and terms change. Re-read the official pricing page before you
promise anything to a client.

If compute quota is exhausted Neon may suspend the project until the quota
resets. That is a recoverable service state:

- The API returns `503` with a database-unavailable error; it does not delete or
  rewrite local data.
- The mobile app keeps cached reads and the outbox. Pending writes stay pending.
- Do **not** clear the outbox, do **not** mark pending records synced, and do
  **not** re-run destructive operations to "fix" it.

### 2.4 Apply the schema

From `server/`:

```bash
export DIRECT_URL='postgresql://...direct...?sslmode=require'
export DATABASE_URL='postgresql://...pooler...?sslmode=require'
npx prisma generate
npm run prisma:status     # expect: no migrations applied yet
npm run prisma:deploy
npm run seed
```

`prisma:deploy` only applies the committed SQL in
`prisma/migrations/20261026000000_init/migration.sql`. Never run
`prisma migrate dev` against production — it can reset the database.

### 2.5 Seed the owner

`npm run seed` reads `SEED_OWNER_*` and `SEED_WORKSPACE_NAME`. It is idempotent:
re-running it does not duplicate the owner or workspace. Choose a strong
password; there is no public sign-up, so this account is the entry point.

Additional team members join only through
`POST /api/v1/workspaces/:id/invitations` (owner/admin), which returns a
one-time code the person redeems at `POST /api/v1/auth/accept-invitation`. There
is no email service — deliver the code out of band.

---

## 3. API host

### 3.1 Requirements

- Node.js 24.x (`engines.node >= 24`).
- HTTPS termination in front of the process. The app refuses to rely on
  cleartext except in the Android debug build.
- Ability to set secrets as environment variables (never a committed `.env`).
- A writable temp directory only. The API is stateless; do not attach a disk.

### 3.2 Build and start

```bash
cd server
npm ci
npx prisma generate
npm run build
NODE_ENV=production node dist/server.js
```

`npm run build` emits ESM into `dist/`. The generated Prisma client lives in
`src/generated/prisma` and is compiled alongside the source; run
`npx prisma generate` before every build so it matches the schema.

### 3.3 Required production environment

`src/config/env.ts` refuses to boot if these are wrong:

| Variable | Production requirement |
| --- | --- |
| `NODE_ENV` | `production` |
| `DATABASE_URL` | Required. Pooled Neon URL. |
| `DIRECT_URL` | Only used by Prisma CLI, not by the running server. |
| `AUTH_SECRET` | Required, at least 16 chars. Generate with `openssl rand -hex 32`. |
| `CORS_ORIGINS` | Comma-separated exact origins, or empty for mobile-only use. |
| `AI_ALLOW_PAID_FALLBACK` | Must stay `false`; the server throws if set to `true` in production. |
| `AI_MONTHLY_BUDGET_USD` | `0` |

`AUTH_SECRET` keys the HMAC that hashes session and invitation tokens. Rotating
it signs every device out and invalidates pending invitation codes. That is the
intended emergency lever.

### 3.4 Health check

```
GET /health  →  200 {"status":"ok","time":"..."}
```

Point the host's health check at it. It does not touch the database, so a Neon
suspend shows up as request failures rather than a failed health check; that is
intentional so the platform does not restart-loop the API.

### 3.5 Reverse proxy notes

- Preserve `X-Forwarded-For`; the app sets `trust proxy` to `1` in production so
  rate limiting sees the real client IP.
- Do not cache `/api/v1/*`.
- Request bodies are capped at `1mb` in `app.ts`; the voice fallback endpoint
  enforces its own smaller limit (`AI_FALLBACK_MAX_BYTES`, default 6 MiB, but the
  audio is base64 inside a JSON body, so keep the proxy limit consistent).
- Terminate TLS at the proxy or platform edge. The Node process itself serves
  plain HTTP.

### 3.6 Logs

- Every request gets an `X-Request-Id`; errors echo it in the JSON envelope.
- Logs are redacted: authorization headers, tokens, passwords, and AI keys are
  never logged. Keep it that way when adding routes.
- Do not log request bodies for `/auth/*` or `/voice/*`.

---

## 4. Mobile release build

### 4.0 Local Android emulator on Windows

These are the exact steps used on the build machine; they are not required for a
store release.

1. Install a JDK 21 (Temurin) and set `JAVA_HOME` (for example
   `C:\tools\jdk21`). Flutter needs a JDK for Gradle.
2. Set `ANDROID_HOME=G:\Android\Sdk` and `ANDROID_SDK_ROOT` to the same path,
   then `flutter config --android-sdk G:\Android\Sdk`.
3. If the AVDs live outside the default folder, set `ANDROID_AVD_HOME` (for
   example `G:\avds`). Each `<name>.ini` must contain an absolute
   `path=<avd folder>\<name>.avd` line; a stale path makes the AVD disappear
   from `emulator -list-avds`.
4. Hardware acceleration is required for a usable emulator. Install the Android
   Emulator Hypervisor Driver (`sdkmanager "extras;google;Android_Emulator_Hypervisor_Driver"`,
   then run `silent_install.bat` **as administrator**) or enable Windows
   Hypervisor Platform and reboot. Without either, boot with `-accel off`; it is
   extremely slow but still useful for a smoke test.
5. Start it and run the debug build against the host API:

```powershell
emulator -avd delivery_emu -no-snapshot-load -gpu swiftshader_indirect
flutter run --debug --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
```

`10.0.2.2` is the emulator's alias for the host machine. Cleartext HTTP is
allowed only in the debug manifest.

**Keep the pub cache on the same drive as the project.** Kotlin's incremental
cache cannot relativize paths across Windows drives and fails the build with
`this and base files have different roots` for every plugin. On this machine the
project is on `G:` while the default pub cache is on `C:`, so the cache was
copied to `G:\pubcache` and the build runs with:

```powershell
$env:PUB_CACHE="G:\pubcache"
flutter pub get      # rewrites .flutter-plugins-dependencies with G: paths
```

`android/gradle.properties` additionally sets `kotlin.incremental=false` and
`kotlin.incremental.useClasspathSnapshot=false` as a second guard.

### 4.1 Point at the deployed API

```bash
flutter build appbundle \
  --dart-define=API_BASE_URL=https://api.example.com/api/v1
```

The base URL must include the `/api/v1` suffix. A release build without the
define does not fall back to localhost: it shows an Arabic "إعداد ناقص" screen
naming the missing define, so a misconfigured build fails visibly instead of
producing an app that cannot connect.

### 4.2 Android

1. Create an upload keystore and `android/key.properties` (copy
   `android/key.properties.example`; never commit either file).
2. `android/app/build.gradle.kts` already reads `key.properties` and uses that
   keystore for release builds. Without the file it falls back to the debug key
   and the bundle cannot be published.
3. `flutter build appbundle --release --dart-define=API_BASE_URL=https://…/api/v1`.
4. Verify `minSdk 24` is acceptable for the target devices.
5. Cleartext HTTP is enabled **only** in
   `android/app/src/debug/AndroidManifest.xml`. Do not copy that attribute into
   the main manifest.

### 4.3 iOS

1. Set the bundle identifier and signing team in Xcode.
2. Confirm `NSMicrophoneUsageDescription` explains the voice feature in Arabic.
3. `NSAllowsLocalNetworking` is present for local development. Production traffic
   must use HTTPS; do not add a blanket `NSAllowsArbitraryLoads`.
4. `flutter build ipa --release --dart-define=...`.

### 4.4 Store checklist

- App label: `مدير الشغل` (already set for Android).
- Arabic-first UI with RTL layout; verify on a real device before shipping — this
  build has only been verified by static analysis.
- Microphone permission rationale must be visible in the store listing.
- Data safety / privacy form: the app stores site, visit, and task text, session
  tokens in platform secure storage, and optionally voice transcripts. Raw audio
  is not retained.

---

## 5. Post-deploy verification

Run these in order against the deployed stack:

1. `GET /health` → 200.
2. `POST /api/v1/auth/login` with the seeded owner → token.
3. `GET /api/v1/auth/me` with the token → user + workspaces.
4. Create a site, a visit, and a task from the app.
5. Toggle airplane mode, create a visit, re-enable network, confirm the pending
   row is pushed once and only once.
6. Edit the same record from a second device, then retry the first edit and
   confirm you get a conflict prompt rather than a silent overwrite.
7. `GET /api/v1/export?format=json&entity=visits` → non-empty array.
8. `GET /api/v1/voice/usage` → limits reported; with no AI keys configured the
   voice endpoints return `AI_UNAVAILABLE` and manual entry still works.
9. Run one backup with `scripts/backup.sh` and restore it into the `dev` branch.

If any step fails, fix it before handing the build over. The current repository
has verified steps 1–8 only at the code/test level, never against a live stack.
