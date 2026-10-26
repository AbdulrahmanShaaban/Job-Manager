# Verification — acceptance checklist

This document records what was actually executed on the build machine and what
was only inspected in source. It exists so nobody can confuse "the code is
written" with "the product was verified".

- **Verified** — a command was run here and the stated result was observed.
- **Code-verified** — the behaviour was traced through the source and, where
  possible, covered by a unit test; it was not exercised on a device or against
  a live service.
- **Unverified** — the required external service, credential, or toolchain was
  not available.

Build machine: Windows 11, Node 24.22, Flutter 3.47.8 / Dart 3.13.7, JDK 21
(Temurin), Android SDK 37 with build-tools 37.0.0, Git 2.56. AEHD 2.2 is
installed and usable (`emulator-check accel` reports `AEHD ... is installed and
usable`). A real Neon project and a real Gemini API key were used. Still
absent: Xcode, `bash`, `pg_dump`, `pg_restore`, and a second physical device.

---

## 0. Build and test evidence

| Check | Command | Result |
| --- | --- | --- |
| Server type-check | `npm run typecheck` | Pass, no output |
| Server build | `npm run build` | Pass, ESM emitted to `dist/` |
| Server tests | `npm test` | 5 files, 24 tests passing |
| Flutter analysis | `flutter analyze` | No issues found |
| Flutter tests | `flutter test` | 4 files, 26 tests passing |
| Dependency pins | `npm ls prisma @prisma/client typescript express zod` | `prisma@7.10.1`, `@prisma/client@7.10.1`, `typescript@7.0.2`, `express@5.3.0`, `zod@4.6.7` |
| Flutter version | `flutter --version` | Flutter 3.47.8, Dart 3.13.7 |
| Neon migration | `npm run prisma:deploy` | Applied `20261026000000_init` to the real Neon branch (`ep-hidden-moon-bap8otvt`) |
| Neon seed | `npm run seed` | Owner `owner@example.com` + workspace `شركة المقاولات` created |
| Live API smoke test | scripted `fetch` run against `http://localhost:3000/api/v1` | health, login, list/create site, create visit, create task, optimistic PATCH 200, stale PATCH 409 `CONFLICT`, overview, voice usage, export CSV — all passed against Neon |
| Gemini Live transport | ephemeral token + WSS handshake | `POST /voice/session-credential` returned 201; the socket reached `setupComplete` and `sessionResumptionUpdate` using the server-issued setup |
| Gemini model IDs | `GET /v1beta/models` with the real key | `gemini-3.8-live` and `gemini-3.5-flash` both exist for this key |\n| Emulator smoke test | AEHD 2.2 install + `emulator -avd delivery_emu` + `adb install` + `am start` | Booted in ~2 min, APK installed (`Success`), `MainActivity` displayed in 45.7s and fully drawn, process alive (`pid 3308`), no `E/flutter` errors in logcat. Screenshot pulled to `app-shot.png` (27.8 KB). |\n| Android release APK | `flutter build apk --release` | `Built build\\app\\outputs\\flutter-apk\\app-release.apk` — 58.5 MB, signed with release keystore (CN=Job Manager, valid until 2054). Supports runtime server URL entry. |
| Android debug APK | `flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1` | `√ Built build\app\outputs\flutter-apk\app-debug.apk` — 172 MB, package `com.jobmanager.job_manager`, version 1.0.0, minSdk 24, targetSdk 36, label `مدير الشغل` |

The APK is a **debug** build, signed with the debug key, and its baked-in API URL
is the emulator alias `10.0.2.2`. Installing it on a physical phone requires
rebuilding with the host's LAN address or a deployed HTTPS API. A release App
Bundle still needs a keystore (`android/key.properties`). iOS was not built: no
macOS/Xcode on this machine.

---

## 1. Product and UI

| Checklist item | Status | Evidence / reason |
| --- | --- | --- |
| App runs on Android and renders in Arabic RTL | **Partially verified** | The debug APK installed and launched on the emulator (accelerated via AEHD 2.2); `MainActivity` displayed and fully drew in 45.7s, process alive, no `E/flutter` errors. The model cannot view the screenshot (image input unsupported), so RTL layout was not visually confirmed by the agent — the user should open `app-shot.png` (27.8 KB) and check the Arabic text direction themselves. |
| My Jobs and Company Sites are distinct and enforce visibility | **Code-verified** | `SiteScope` drives separate tabs and pickers; server scoping is covered by `tests/authz.test.ts` (personal sites private, company sites require membership). Not exercised on two devices. |
| Create/edit/search site; view address, map link, notes | **Code-verified** | `site_form_screen.dart` (create/edit), `site_detail_screen.dart` (map + phone via `url_launcher`), search on the server and in `LocalDb.readSites`. Not exercised on a device. |
| Multiple dated visits per site, history in local date order | **Code-verified** | Visits are append-only; `visitHistoryProvider` orders by date; date-only handling is unit-tested. UI ordering not observed on a device. |
| Completed work, remaining work, and open tasks are not confused | **Code-verified** | Separate models/tables and separate UI sections; visits never render as tasks. |
| Authorized team members see company-site updates from another account/device | **Unverified** | Requires a live database and two clients. Server-side role checks are unit-tested, but cross-device propagation was never observed. |
| Every voice workflow has a manual equivalent | **Code-verified** | Manual visit form, manual task form, and manual task update exist and are reachable from the dashboard, site detail, and voice screen. |
| Design uses real data, no fake metrics or decorative AI | **Code-verified** | Dashboard metrics come from `GET /overview`; no hard-coded counts. Voice card links to the real assistant. |

---

## 2. Database and sync

| Checklist item | Status | Evidence / reason |
| --- | --- | --- |
| Prisma migrations create the expected tables and indexes on a Neon development branch | **Verified** | `npm run prisma:deploy` applied `20261026000000_init` to the real Neon branch; `npm run seed` then wrote the owner and workspace, and the live smoke test created and read sites, visits, and tasks through the API. `tests/migration.test.ts` additionally asserts tables, constraints, indexes, and the visit date index in PGlite. |
| Production migrations are applied only after validation | **Verified for the deploy path** | `prisma migrate deploy` (never `migrate dev`, which can reset) was the command used against Neon. No separate production database exists yet. |
| Ownership/workspace authorization is tested for every read/write endpoint | **Partial** | Role ladder, personal/company scoping, and assistant tool scoping are unit-tested; every route handler was reviewed, but there is no integration suite that hits all endpoints against a database. |
| Offline visits/tasks are preserved and synced after reconnect | **Unverified end-to-end** | Outbox, optimistic rows, id remapping, and failed-item retry are implemented and reviewed; only the outbox row round-trip is unit-tested. No airplane-mode run was possible. |
| Replayed operations do not create duplicate rows | **Code-verified** | Unique `operationId` constraints are asserted in the migration test; create routes look up the operation id before inserting. Not replayed against a live database. |
| Date-only visit entries do not shift due to UTC conversion | **Verified** | `tests/dates.test.ts` covers round-trips, UTC-midnight boundaries, and Cairo summer/winter offsets; the migration test stores a date-only value and reads the same calendar day. |
| Backup export is created and a restore test succeeds | **Unverified** | `scripts/backup.sh` / `restore.sh` were written and reviewed, but `bash`, `pg_dump`, and `pg_restore` are absent and there is no Neon database to dump. |

Additional sync behaviour added during hardening:

- A queued site create now remaps the optimistic site id to the server id and
  rewrites child rows and queued bodies (`LocalDb.remapSiteId`).
- Optimistic rows are removed when a write fails permanently, so a rejected
  create cannot linger as a phantom duplicate.
- Failed writes are terminal until the user retries them; they are listed in
  Settings with retry/discard actions.

---

## 3. Voice and zero-cost operation

| Checklist item | Status | Evidence / reason |
| --- | --- | --- |
| Assistant understands curated Egyptian Arabic sentences, site names, dates, counts | **Unverified (content quality)** | Transport is verified: a server-minted ephemeral token completes a real Gemini Live handshake. No audio turn was sent, so Arabic speech recognition and reply quality were not observed. |
| Assistant asks a targeted question for ambiguous sites or critical values | **Code-verified** | Tool schemas require a site or return candidates; prompts instruct the model to ask instead of guessing. Not observed live. |
| Assistant answers queries only from authorized saved data | **Code-verified** | `POST /voice/tool` re-authenticates the session and scopes every query to the user/workspace; `tests/tool-actions.test.ts` asserts the search is scoped and returns real counts. |
| Every write appears as a draft and requires confirmation | **Code-verified** | Server tool results carry `requiresConfirmation`; the client parses them into `AssistantDraft` and only writes in `confirmDraft`. Model tests cover draft parsing. |
| Gemini quota/service failure activates the fallback pipeline | **Code-verified** | Provider router falls through to the next free provider; unit tests cover fall-through, cool-down, 5xx, and exhaustion. No live failure was induced. |
| If all free providers fail, the draft and manual entry are preserved | **Code-verified** | `_failLive` keeps the draft and switches to review/unavailable; the voice screen links to manual visit and task entry. |
| No paid request is made when `AI_ALLOW_PAID_FALLBACK=false` | **Verified at code/test level** | Env validation refuses `true` in production; `assertFreeOnlyMode()` and `assertAiBudget()` run before minting a session; the router only registers free providers. No paid provider is even wired. |
| No permanent API key in the app binary, logs, or client responses | **Code-verified** | The app receives only a short-lived Live token; the permanent key stays server-side. Tokens are HMAC-digested in the database and redacted from logs. Not penetration-tested. |
| No raw audio stored by default | **Code-verified** | The client deletes each fallback WAV in a `finally` block; the server never writes audio to disk or the database. Transcript retention is gated by `TRANSCRIPT_RETENTION_ENABLED` and the user's `keepTranscripts` setting. |

---

## 4. Quality

| Checklist item | Status | Evidence / reason |
| --- | --- | --- |
| TypeScript 7.0.2 type-check/build with the final package set; tests for the Prisma/Neon adapter and provider router | **Partial** | Type-check, build, and the full test suite pass with `typescript@7.0.2`. The provider router is tested. The Prisma/Neon adapter has no dedicated test because it needs a live Neon connection. |
| Server validates requests and does not expose secrets or stack traces | **Code-verified** | Zod validation on every route, one error envelope with `requestId`, production error handler hides internals, and the logger redacts authorization/tokens/keys. |
| No Prisma 8 RC or beta package introduced | **Verified** | `package.json` pins `prisma` and `@prisma/client` to `7.10.1`; `npm ls` confirms the installed tree. |
| No paid plan, billing upgrade, or automatic charge enabled | **Verified** | No billing integration exists. `AI_MONTHLY_BUDGET_USD=0`, `AI_ALLOW_PAID_FALLBACK=false`, and every AI key is optional and blank by default. |

---

## 5. Deliberate limitations (not bugs to report as missing features)

These are known, documented gaps rather than accidental omissions:

- Tasks are soft-cancelled (`CANCELLED` status); there is no tombstone or hard
  delete, so a deleted task can still appear in an old export.
- Visits are append-only and editable, but there is no `VisitRevision` audit
  table: the previous text of an edited visit is not retained.
- Login is rate-limited per IP, not per account.
- Invitation codes cannot be revoked before they are redeemed; rotating
  `AUTH_SECRET` invalidates all of them at once.
- `Session.lastUsedAt` is never updated.
- Provider cool-downs are in-memory, per process.
- Exports are bounded (1000 sites, 100 visits/site, 100 tasks/site, 1000
  personal tasks) and signal truncation with `x-export-truncated: true`; they are
  not paginated.
- There is no background sync worker, no push notification, and no photo
  storage. These are explicit non-goals in the spec.

---

## 6. What must be done before calling this production-ready

Done in this environment:

1. ~~Create the Neon project, set `DATABASE_URL`/`DIRECT_URL`/`AUTH_SECRET`, run
   `npm run prisma:deploy`, `npm run seed`~~ — completed against the real Neon
   branch, then exercised end to end through the API.

Still required:

2. Deploy the API over HTTPS and run the post-deploy list in
   `docs/DEPLOYMENT.md` §5, including the airplane-mode and two-device conflict
   checks.
3. Install the app on physical Android and iOS devices in Arabic RTL, and create
   a release keystore (`android/key.properties`, template in
   `android/key.properties.example`) before any store upload.
4. Run the Egyptian-Arabic voice test set on a device, including
   quota-exhaustion and provider-failure paths.
5. Run one backup and one restore drill with `pg_dump`/`pg_restore` against a
   throwaway Neon branch.
6. Rotate the Neon password, the Gemini key, and `AUTH_SECRET` if any of them
   were shared in plain text during setup.

Until those steps are executed, the corresponding rows above stay **Unverified**.
