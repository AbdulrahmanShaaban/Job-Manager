# Job Manager — مدير الشغل

Arabic-first (Egyptian) field-work tracker for site visits and follow-up tasks.
Two clearly separated sections:

| Section | Arabic | Visibility |
| --- | --- | --- |
| **Company sites** | مواقع الشركة | Shared with the workspace |
| **My jobs** | شغلي | Private to the signed-in user |

Visits are append-only history. Tasks are live operational state. A voice
assistant drafts visits, tasks, and task updates in Egyptian Arabic — but every
write is a draft that the user must explicitly confirm.

```
Flutter (Android / iOS)  ──HTTPS──▶  Express 5 API  ──▶  Neon PostgreSQL
        │                                  │
        └── SQLite cache + outbox          └── Gemini Live / free fallback
```

---

## 1. Status of this build

This section is deliberately blunt. Read it before demoing anything.

### Verified in this environment

| Area | Evidence |
| --- | --- |
| Server type-checks and builds | `npm run typecheck`, `npm run build` → 47 files emitted to `dist/` |
| Server test suite | `npm test` → 5 files, 24 tests passing |
| Migration SQL is valid PostgreSQL | `tests/migration.test.ts` runs the real migration in PGlite and asserts tables, constraints, indexes |
| Live Neon database | `npm run prisma:deploy` applied `20261026000000_init` to the real branch; `npm run seed` created the owner and workspace |
| Full API flow against Neon | health, login, create/list site, create visit, create task, optimistic PATCH 200, stale PATCH → 409 `CONFLICT`, overview, voice usage, CSV export — all passed |
| Gemini Live | real key minted an ephemeral token (201) and the socket reached `setupComplete` + `sessionResumptionUpdate` |
| Flutter static analysis | `flutter analyze` → no issues |
| Flutter unit tests | `flutter test` → 4 files, 26 tests passing |
| Android debug APK | `flutter build apk --debug` → `app-debug.apk`, label `مدير الشغل`, minSdk 24, targetSdk 36 |
| Dependency pins resolve | `flutter pub get`, `npm ci`-style install |

### Not verified — needs a device, an OS, or an extra credential

| Area | Why it is unverified |
| --- | --- |
| Running the app on a screen | No hardware hypervisor for the emulator (needs an admin install + reboot) and no physical device. RTL layout and on-device usability were never seen. |
| Arabic voice quality | The Live transport works, but no audio turn was sent: speech recognition accuracy and reply quality are unmeasured. |
| Free fallback chain (Groq) | `GROQ_API_KEY` is blank by design, so the Whisper → text-LLM path is inert until a free Groq key is added. |
| Cross-device sync | Needs two signed-in devices against one workspace. |
| iOS build | No macOS/Xcode. |
| Release signing / store upload | No keystore; the APK above is debug-signed. |
| Backup/restore scripts | `bash`, `pg_dump`, and `pg_restore` are not installed here, so the scripts were reviewed but never executed. |
| Automated off-site backups | Deliberately out of scope for the $0 MVP (see `docs/DATABASE_BACKUP.md`). |

Do not report an item from the second table as "done" without running it.

### Run it now

```powershell
# API — the Neon branch is already migrated and seeded
cd server
npm install
npm run prisma:generate
npm run dev            # http://localhost:3000/health

# App — a debug APK is already built
#   mobile\build\app\outputs\flutter-apk\app-debug.apk
#   it targets http://10.0.2.2:3000/api/v1, i.e. the API on the host machine
#   from an Android emulator
```

Sign in with `SEED_OWNER_EMAIL` / `SEED_OWNER_PASSWORD` from `server/.env`.
For a physical phone, rebuild with the PC's LAN address
(`--dart-define=API_BASE_URL=http://<PC-IP>:3000/api/v1`) and allow port 3000
through the firewall; `10.0.2.2` only exists inside the emulator.

---

## 2. Repository layout

```
G:\Job Manager
├── Job-Manager-Final-Build.md      # authoritative product/technical spec
├── README.md                       # this file
├── docs/
│   ├── DEPLOYMENT.md               # Neon + API host + mobile build
│   ├── DATABASE_BACKUP.md          # backup policy, scripts, restore drill
│   ├── AI_PROVIDER_NOTES.md        # $0 voice stack, quotas, swap-in points
│   └── VERIFICATION.md             # acceptance checklist with evidence
├── server/                         # Express 5 + TypeScript + Prisma 7
│   ├── prisma/schema.prisma
│   ├── prisma/migrations/20261026000000_init/migration.sql
│   ├── prisma/seed.ts
│   ├── scripts/backup.sh
│   ├── scripts/restore.sh
│   ├── src/
│   │   ├── app.ts                  # middleware + router mounting
│   │   ├── server.ts
│   │   ├── config/env.ts           # Zod-validated environment
│   │   ├── db/prisma.ts            # Neon adapter + pooled connection
│   │   ├── middleware/             # auth, errors, rate limit, request id
│   │   ├── modules/                # auth, workspaces, sites, visits, tasks,
│   │   │                           # overview, export, voice
│   │   ├── shared/                 # authz, dates, errors, serializers, tokens
│   │   └── generated/prisma/       # Prisma client (generated, not committed)
│   └── tests/
└── mobile/                         # Flutter app
    └── lib/
        ├── app.dart                # ShadApp + router + theme
        ├── core/                   # config, api client, session store, speech
        ├── data/                   # repository, SQLite, outbox, sync
        ├── models/                 # Site, Visit, Task, User, Overview, Voice
        ├── state/                  # Riverpod providers + voice controller
        └── features/               # auth, shell, dashboard, sites, visits,
                                    # tasks, voice, settings
```

The repository is initialised on branch `main` with `origin` pointing at
`https://github.com/AbdulrahmanShaaban/Job-Manager.git`. `server/.env`, keystores,
`key.properties`, `build/`, and `node_modules/` are ignored — never commit them.
`server/src/generated/prisma` is ignored too; run `npm run prisma:generate` after
cloning (there is no `postinstall` hook).

---

## 3. Prerequisites

| Tool | Version used here | Notes |
| --- | --- | --- |
| Node.js | 24 LTS | `engines.node >= 24`. Node 22 is not tested. |
| npm | bundled with Node 24 | On Windows PowerShell, `npm` may be blocked by execution policy; use `npm.cmd`. |
| Flutter | 3.47.8 (Dart 3.13.7) | `mobile/pubspec.yaml` requires `flutter >= 3.47.0` |
| PostgreSQL client tools | 16+ | Only needed for `backup.sh` / `restore.sh` |
| Android SDK | 37 (build-tools 37.0.0) | Only needed to build an APK; platform 36 is what the app compiles against. |
| JDK | 21 (Temurin) | Required by the Android Gradle build. |

Pinned versions of note: Express `5.3.0`, TypeScript `7.0.2`, Prisma `7.10.1`
(Prisma 8 is still a release candidate and is intentionally **not** used),
Zod `4.6.7`, `shadcn_ui` `0.57.3`, Riverpod `3.4.3`, `go_router` `18.1.1`.
All dependency ranges are exact pins — no `^` or `~` in production
dependencies.

---

## 4. Server setup

```bash
cd server
cp .env.example .env      # then fill in the values
npm install
npx prisma generate
npm run prisma:deploy     # applies prisma/migrations to DIRECT_URL
npm run seed              # creates the owner + default workspace
npm run dev               # http://localhost:3000/health
```

`npm run prisma:deploy` uses `DIRECT_URL` (the non-pooled Neon endpoint);
runtime queries use `DATABASE_URL` (the pooled endpoint). See
`docs/DEPLOYMENT.md` for why both exist.

### Environment variables

All values are validated at boot by `src/config/env.ts`; the process refuses to
start with a missing or malformed value. See `.env.example` for the annotated
list. Summary:

| Group | Variables |
| --- | --- |
| Runtime | `NODE_ENV`, `PORT`, `CORS_ORIGINS` |
| Database | `DATABASE_URL` (pooled), `DIRECT_URL` (direct) |
| Sessions | `AUTH_SECRET`, `SESSION_TTL_DAYS` |
| Seed owner | `SEED_OWNER_NAME`, `SEED_OWNER_EMAIL`, `SEED_OWNER_PASSWORD`, `SEED_WORKSPACE_NAME` |
| Gemini Live | `GEMINI_API_KEY`, `GEMINI_LIVE_MODEL`, `GEMINI_TEXT_MODEL` |
| Free fallback | `GROQ_API_KEY`, `GROQ_STT_MODEL`, `GROQ_LLM_MODEL` |
| Cost guards | `AI_MONTHLY_BUDGET_USD=0`, `AI_ALLOW_PAID_FALLBACK=false`, `AI_MAX_SESSION_SECONDS`, `AI_MONTHLY_SESSION_LIMIT`, `AI_MONTHLY_MINUTES_LIMIT` |
| Privacy | `TRANSCRIPT_RETENTION_ENABLED=false` |
| Fallback limits | `AI_FALLBACK_MAX_BYTES`, `AI_FALLBACK_MAX_SECONDS` |

Leaving every AI variable blank is a supported configuration: the voice
endpoints return `AI_UNAVAILABLE` and the app keeps manual entry working.

### Scripts

| Command | Purpose |
| --- | --- |
| `npm run dev` | Watch-mode API on `PORT` |
| `npm run build` | Emit `dist/` via `tsconfig.build.json` |
| `npm start` | Run the built server |
| `npm run typecheck` | `tsc --noEmit` |
| `npm test` | Vitest suite (no database required) |
| `npm run prisma:generate` | Regenerate the client into `src/generated/prisma` |
| `npm run prisma:deploy` | Apply migrations (production-safe) |
| `npm run prisma:status` | Show migration state |
| `npm run seed` | Idempotent owner + workspace seed |
| `npm run backup` | `scripts/backup.sh` — logical dump outside the repo |
| `npm run restore` | `scripts/restore.sh` — restore with a confirmation gate |

---

## 5. Mobile setup

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
```

Default API base URL when no `--dart-define` is supplied:

- Android emulator → `http://10.0.2.2:3000/api/v1`
- Everything else → `http://127.0.0.1:3000/api/v1`

**Release builds must supply `--dart-define=API_BASE_URL=…`.** A release build
without it shows an Arabic "إعداد ناقص" screen instead of silently calling
localhost. The URL must include the `/api/v1` suffix.

Cleartext HTTP is allowed only in the debug manifest
(`android/app/src/debug/AndroidManifest.xml`). Release builds must use HTTPS.

### Android release signing

`android/app/build.gradle.kts` reads `android/key.properties` when it exists and
falls back to the debug key otherwise (local testing only). Copy
`android/key.properties.example` to `android/key.properties`, point it at your
keystore, and keep both the properties file and the `.jks` out of source
control.

Platform permissions already declared:

- Android: `INTERNET`, `RECORD_AUDIO`, `minSdk 24`, app label `مدير الشغل`
- iOS: `NSMicrophoneUsageDescription`, `NSAllowsLocalNetworking`

### Screens

| Screen | File |
| --- | --- |
| Sign in | `features/auth/login_screen.dart` |
| Shell / bottom navigation | `features/shell/home_shell.dart` |
| Dashboard | `features/dashboard/dashboard_screen.dart` |
| Sites (company / mine) | `features/sites/sites_screen.dart` |
| Create / edit site | `features/sites/site_form_screen.dart` |
| Site details | `features/sites/site_detail_screen.dart` |
| Visit history + editor | `features/visits/visit_form_screen.dart` (opened from site details) |
| Tasks | `features/tasks/tasks_screen.dart` + `task_form_screen.dart` |
| Voice assistant | `features/voice/voice_screen.dart` + `draft_review.dart` |
| Settings | `features/settings/settings_screen.dart` |

Bottom navigation order: Dashboard → Sites → Voice → Tasks → Settings.

---

## 6. API surface

Base path `/api/v1`. Errors always use:

```json
{ "error": { "code": "VALIDATION_ERROR", "message": "...", "details": {}, "requestId": "..." } }
```

| Method + path | Notes |
| --- | --- |
| `POST /auth/login` | Email + password → opaque bearer token |
| `POST /auth/accept-invitation` | One-time invitation code + new password |
| `POST /auth/logout` | Revokes the current session |
| `GET /auth/me` | Current user + workspaces |
| `GET /workspaces` | Memberships |
| `GET /workspaces/:id/members` | Owner/admin |
| `POST /workspaces/:id/invitations` | Owner/admin, returns one-time code |
| `GET /sites?scope=personal\|company` | Scoped listing |
| `POST /sites` | `scope` decides workspace vs private |
| `GET /sites/:id` | Includes open task count and last visit |
| `PATCH /sites/:id` | Optimistic concurrency via `baseUpdatedAt` |
| `GET /sites/:id/visits` | Append-only history |
| `POST /sites/:id/visits` | Idempotent on `operationId` |
| `PATCH /visits/:id` | Corrects a recorded visit |
| `GET /tasks?siteId=&status=` | Live task list |
| `POST /tasks` | Idempotent on `operationId` |
| `PATCH /tasks/:id` | Status/priority/assignee |
| `DELETE /tasks/:id` | Soft-cancels |
| `GET /overview` | Dashboard aggregates |
| `GET /export?format=json\|csv&entity=sites\|visits\|tasks` | Portable export |
| `POST /voice/session-credential` | Ephemeral Gemini Live token; never the permanent key |
| `POST /voice/sessions/:id/complete` | Close a voice session |
| `POST /voice/tool` | Server-validated tool call from the model |
| `POST /voice/fallback-turn` | Short audio turn → STT → LLM → reply |
| `GET /voice/usage` | Session/minute estimates against configured limits |

Error codes: `VALIDATION_ERROR` (422), `UNAUTHORIZED` (401), `FORBIDDEN` (403),
`NOT_FOUND` (404), `CONFLICT` (409, with `details.serverUpdatedAt`),
`RATE_LIMITED` (429), `AI_UNAVAILABLE` (503), `AI_QUOTA_EXHAUSTED` (429).

### Authorization rules

- Every query is scoped to the authenticated user or a workspace they belong to.
- A guessed UUID is not authorization: membership is re-checked per request.
- Company sites require workspace membership; personal sites are visible only to
  their owner.
- Workspace mutations (invitations, membership) are owner/admin only.

### Concurrency and idempotency

- Writes that can be retried carry a client-generated `operationId` (UUID). The
  server records it, so a replay returns the original result instead of creating
  a duplicate visit or task.
- Updates carry `baseUpdatedAt`. If the server row moved on, the response is
  `409 CONFLICT` with `details.serverUpdatedAt`, and the client surfaces a
  reload/reconcile choice. Nothing is silently overwritten.

---

## 7. Offline-first behaviour

- SQLite (`sqflite`) caches recently used sites, open tasks, and visit history.
- New visits and tasks are written locally with `pending: true` and queued in an
  outbox table with a client operation UUID.
- The outbox is drained by a foreground `Timer.periodic(30s)`, on app resume, and
  immediately after a successful write. There is no background worker, no Redis,
  and no queue service — the spec forbids them for this MVP.
- Conflicts are never auto-resolved. The settings screen lists them and offers an
  explicit keep-local / keep-server choice.
- Writes rejected by the server (validation, permissions) are marked failed and
  are **not** retried automatically. Settings lists them with a retry
  («جرّب تاني») and a discard («امسح») action so the user decides.
- If the server is unreachable, cached data stays readable and drafts stay
  editable. Nothing is marked synced until the server acknowledges it.
- Voice needs network. When it is unavailable, the draft text and the manual
  forms remain fully usable.

---

## 8. Voice assistant and the $0 rule

- The Flutter app **never** holds a permanent provider key. The server issues a
  short-lived Gemini Live credential; the app connects with that.
- Live sessions run with text response modality and device-side TTS, so no paid
  audio-output path is required.
- Fallback chain: record a short turn → Groq Whisper STT → text LLM → device TTS.
  The optional Azure TTS path was removed because it requires a credit card.
  Leave `GROQ_API_KEY` blank to run Gemini Live only.
- Hard guards: `AI_ALLOW_PAID_FALLBACK=false`, `AI_MONTHLY_BUDGET_USD=0`,
  per-session seconds cap, monthly session/minute soft limits with warnings.
- When every free provider is exhausted the server returns `AI_QUOTA_EXHAUSTED`
  and the app stops calling AI, keeps the transcript/draft, and points the user
  at manual entry. It never claims unlimited free voice.
- Raw audio is not retained. Transcript retention is off by default and is a
  user-facing setting.

Details, quotas, and swap-in points: `docs/AI_PROVIDER_NOTES.md`.

---

## 9. Backup

Neon Instant Restore is a 6-hour recovery window, not a backup policy. The
supported policy is:

1. `server/scripts/backup.sh` → `pg_dump -Fc` custom/compressed archive, written
   outside the repository, verified with `pg_restore --list`, plus a SHA-256
   sidecar.
2. Copy that file to storage outside the Neon account.
3. `server/scripts/restore.sh <dump> <target-url>` to restore into a throwaway
   branch first, then production, with an explicit typed confirmation.
4. In-app export (`GET /export`, and Settings → export) for vendor-independent
   JSON/CSV copies of sites, visits, and tasks. The file is written to the app's
   documents directory and handed to the system share sheet (`share_plus`) so it
   can be saved or sent on Android and iOS.

Full policy and the restore drill: `docs/DATABASE_BACKUP.md`.

---

## 10. Testing

```bash
cd server && npm run typecheck && npm test && npm run build
cd mobile && flutter analyze && flutter test
```

Server tests cover date handling in `Africa/Cairo`, authorization scoping, the
provider router's $0 guards, tool-argument validation, and the real migration SQL
executed in PGlite. Mobile tests cover date/number formatting, model JSON
round-trips, outbox/idempotency behaviour, and the state-copy semantics that keep
voice drafts and sync errors from being wiped by unrelated updates.

There are no widget or end-to-end tests yet, and no test runs against a live
Neon database or live AI provider. `docs/VERIFICATION.md` maps every acceptance
checklist item to the evidence that actually exists.

---

## 11. Deliberate non-goals

No pricing, cost, profit, or accounting features. No MongoDB, Redis, Docker,
microservices, photo capture, or open public sign-up. No AI feature that requires
a paid tier to function. See `docs/VERIFICATION.md` for the acceptance checklist
and the exact reason each unverified item is unverified.
