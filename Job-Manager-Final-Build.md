# Job Manager — Final Build Specification

**Document date:** 26 October 2026  
**Purpose:** Build a lightweight, Arabic-first Flutter app for recording work-site visits, tracking remaining tasks, and querying this information through an Egyptian-Arabic voice assistant.  
**Budget rule:** Target $0 recurring cost. Never call a paid AI API automatically. If all free quotas are exhausted, preserve the draft and fall back to manual text entry.

> **Coding-agent instruction:** Read this entire specification before modifying the repository. The three reference screenshots supplied with the task describe the old app's workflows, not a pixel-perfect design to copy. Preserve the useful concepts and modernize the UI. Verify current package/API availability and compatibility before coding. Do not add paid dependencies, a paid service, Redis, Docker, microservices, or unrelated features without explicit approval.

---

## 1. Product requirements from the client

The client needs a normal mobile app to avoid relying on memory or WhatsApp messages when revisiting a work site.

### Main usage

1. The app has two clear sections/tabs:
   - **Company Sites** — shared sites that authorized team members can view and update, so the next person arriving at a site knows what remains.
   - **My Jobs** — the user's own jobs, separate from company sites.
2. Each site has a name, address/area, optional map URL or coordinates, optional contact details, general notes, and a current to-do list.
3. The same site can be visited many times. Every visit is a dated historical entry with what was completed, what remains, and additional notes.
4. Tasks that are still open remain visible across visits until someone marks them complete. A visit's historical notes must not be silently rewritten when a task changes later.
5. The user can search a site and see its history from another device after signing in. Authorized company members can see shared company-site notes and remaining tasks.
6. There is an editable manual-entry path for every major operation.
7. The main differentiator is a voice assistant, similar in interaction style to Siri: the user speaks naturally in Egyptian Arabic, the assistant asks for missing details, prepares a visit/task update, reads back a concise summary, and saves only after confirmation.
8. The assistant can answer questions grounded in saved records, such as:
   - “إيه اللي متبقي في موقع قرنفل؟”
   - “أنا عملت إيه في مصنع صدره يوم 20 أكتوبر؟”
   - “سجل زيارة النهارده، خلصنا تركيب كاميرتين ولسه تلاتة.”
9. **Do not add price, cost, profit, or accounting features in the MVP.** The client explicitly said these are not important.
10. Site/visit photo attachment can be considered after the core product works. Do not introduce storage cost or a complicated upload pipeline in the initial build.

### Example workflow

User: “سجل زيارة النهارده، خلصت تركيب كاميرتين ولسه تلاتة في مصنع صدره.”

- If the site is unambiguous, the assistant prepares a visit draft for that site.
- It records the local visit date, completed work, remaining work, and any clear notes.
- If a key detail is ambiguous, it asks one short follow-up question instead of guessing.
- It checks current open tasks and proposes any task changes separately.
- It reads back the visit and task changes.
- Nothing is saved until the user says yes or taps **Confirm**.

---

## 2. Final technology decisions

Use current stable releases that are compatible with one another. Keep exact versions in lockfiles; do not use wildcard dependencies.

### Mobile app

- **Flutter stable + Dart stable** for Android first and iOS where build tooling is available.
- **UI components:** `shadcn_ui` for Flutter, using its current stable compatible version (version **0.57.3** was the latest stable observed on 26 October 2026). It is a community-maintained Flutter port, not an official Flutter package; validate RTL, accessibility, Android performance, and required component coverage before committing to it.
- Use Flutter's native widgets for any component that is missing, unstable, or has an RTL issue. Do not add a second large UI framework just to fill small gaps.
- **State management:** `flutter_riverpod` (version **3.4.3** was the latest stable observed on 26 October 2026), after compatibility verification with the selected Flutter/Dart SDK.
- **Navigation:** `go_router`, latest stable compatible version.
- **HTTP:** `dio` or Flutter's standard HTTP client. Choose one, not both without a real need.
- **Local/offline storage:** SQLite with a maintained Flutter package such as `drift`/`drift_flutter` or `sqflite`. Prefer typed migrations and reactive queries if Drift fits the supported SDK; otherwise use sqflite for the simpler implementation.
- **Audio:** choose a maintained plugin that supports the precise live PCM/audio formats and stream handling required by the chosen Live API. Verify Android/iOS microphone permissions and interruption behavior with a small spike before implementing the full voice screen.
- Use the latest **stable** Flutter channel available when implementation begins. As checked on 26 October 2026, the official release documentation identified Flutter 3.47 as the released stable line; Flutter 3.50 was scheduled for November, so do not treat it as stable before the official stable release.

### Backend

- **Node.js 24 LTS + Express 5 + TypeScript 7.0.2**.
- TypeScript **7.0.2** is intentional, not a typo. It was the latest stable npm version found during the check on 26 October 2026. TypeScript 7.1 was beta at that time; do not use beta/nightly in production.
- Before building the whole server, verify TypeScript 7.0.2 compatibility with the selected Express, Prisma, adapters, test runner, linting, and build tools. Run a small compile/typecheck/integration proof first. Do not silently downgrade TypeScript. If a verified blocking incompatibility exists, report the exact evidence and the smallest practical alternative.
- Keep Express as a single small API service. Do not switch to Go or Rust: the project is CRUD + sync + provider calls, and AI/network latency will dominate ordinary backend execution time.
- Use ESM consistently. Follow the selected Prisma major version's current official config, client-generation, and adapter instructions; do not copy Prisma 6 snippets into Prisma 7/8 projects.
- Validate API request bodies with Zod or another small maintained schema validator. Keep routing, validation, business logic, and provider handling understandable without creating unnecessary abstractions.

### Prisma version policy

- **Use Prisma ORM 7.10.1 as the default stable target** based on the official release information checked on 26 October 2026. Keep `prisma` and `@prisma/client` on matching Prisma 7 versions, and use the matching supported Neon/driver adapter.
- **Prisma ORM 8 was still marked Release Candidate** in the official documentation during this check, and some features were still listed as unavailable. Do not use the RC merely to claim “latest tech.” At the start of implementation, recheck its status. If Prisma 8 has reached General Availability and the required PostgreSQL/Neon adapter plus TypeScript 7.0.2 compatibility are verified, the coding agent may recommend it before adopting it; otherwise stay on Prisma 7 stable.
- Prisma 7 requires a driver adapter for direct database connections and uses ESM-oriented configuration. Follow the current Prisma 7 docs for `prisma.config.ts`, generated-client setup, migrations, and the Neon adapter.
- Do not remove Prisma. The project must use Prisma models, typed access, and migrations.

### Database

- **PostgreSQL hosted on Neon**. Do not switch to MongoDB: sites, visits, tasks, workspace membership, and their access rules are relational. PostgreSQL is the better fit and avoids changing the client’s data model just to chase a “lighter” database.
- **Prisma ORM** is the database access layer.
- Use Neon's pooled connection endpoint for runtime if supported by the chosen Prisma adapter, and the direct/non-pooled endpoint for migrations when required by the selected Prisma version. Keep the URLs separate in environment variables and confirm the current Neon/Prisma setup guide before deployment.
- Use a development branch/database for migration testing; apply migrations to production only after they pass on development data.
- The app may use local SQLite for offline drafts/cache, but PostgreSQL on Neon is the central synced source of truth.

---

## 3. UI direction and supplied reference screenshots

The reference screenshots show the existing app's useful concepts: a site list, **My jobs / Company sites** tabs, site details, location link and map actions, general notes, a to-do list, photos, and a dated visit log. If using the companion ZIP, inspect `references/01-sites-list-and-tabs.jpg`, `references/02-site-details-map-notes-tasks.jpg`, and `references/03-visit-history-and-photos.jpg`. Treat these as workflow references, not a pixel-perfect design target.

Build a fresh, polished mobile UI rather than copying the old web-style layout exactly.

### Visual direction

- Arabic-first, correct RTL on every screen, including forms, dates, tabs, dialogs, navigation, and directional icons.
- Dark theme can be the default because the old app uses a dark UI. Include a coherent light theme if it is easy to support through the chosen component system.
- Use a restrained accent color for primary actions, clear typography, generous tap targets, short labels, and consistent spacing.
- Use real shadcn-style components where appropriate: buttons, cards, inputs, text areas, tabs, sheets/dialogs, select fields, date pickers, toast/sonner notifications, and accessible loading/error states.
- Do not use generic AI-chat gradients, fake dashboards, pretend statistics, decorative animations, or excessive cards.
- Design for use while standing at a work site: fast search, visible open tasks, a big voice action, clear save/confirm actions, and good contrast outdoors.
- Respect Android system navigation/keyboard insets, microphone permission states, large text, and screen readers.

### Required screens

1. **Dashboard** — quick voice action, search, recently updated sites, today’s visits, and open tasks. Only show real computed information; no fake metrics.
2. **Sites** — search plus segmented/tabs for “مواقع الشركة” and “شغلي”; filters for active/archived.
3. **Create/edit site** — name, address/area, optional contact/phone, map URL, optional coordinates, general notes, and scope (personal/company where permissions allow).
4. **Site details** — site information and map action, general notes, current to-do list, recent visit, full visit history, and quick actions to add a visit/task.
5. **Visit history/editor** — date, completed work, remaining work, notes, author, and optionally a reference transcript. Historical visits are append-only by default; edits require explicit user action and update metadata.
6. **Tasks** — open/in-progress/completed filters, title, description, site, priority, optional due date, and completion/reopen actions.
7. **Voice assistant** — microphone/live connection status, transcript where available, assistant response, stop/end action, fallback state, and a review screen before committing changes.
8. **Settings** — account/workspace, privacy/transcript retention, data export/backup, AI availability/usage status, and sign-out.

---

## 4. Core data model using Prisma + PostgreSQL

Use UUID identifiers, foreign keys, indexes, timestamps, transactions where multiple records change, and migrations tracked in version control. Final Prisma model names and fields can be refined during implementation, but retain these concepts.

### `User`
- `id`, `name`, unique `email`, `passwordHash` or auth-provider identity, `createdAt`, `updatedAt`.
- Never store plaintext passwords.

### `Workspace`
- Represents the company/team sharing the company sites.
- Fields: `id`, `name`, `createdAt`, `updatedAt`.

### `WorkspaceMember`
- Links users to a workspace with a role such as `OWNER`, `EDITOR`, or `VIEWER`.
- Unique `(workspaceId, userId)`.
- A company-site read/write must check workspace membership and role on the server.

### `Site`
- `id`, `name`, `scope` enum (`PERSONAL` or `COMPANY`), `ownerUserId` for personal sites, `workspaceId` for company sites, `address`, `contactName?`, `contactPhone?`, `mapUrl?`, `latitude?`, `longitude?`, `generalNotes?`, `status`, `createdAt`, `updatedAt`, `createdById`.
- Personal sites are private to their owner by default. Company sites belong to a workspace and are visible only to its members.
- Validate the invariant between `scope`, `ownerUserId`, and `workspaceId`; do not rely on AI to determine access.

### `Visit`
- `id`, `siteId`, `visitDate` (date-only semantics, interpreted in `Africa/Cairo` for the current client), `completedWork`, `remainingWork?`, `notes?`, `createdById`, `source` (`MANUAL` or `VOICE`), `createdAt`, `updatedAt`.
- Index `(siteId, visitDate DESC)`.
- Each visit is a separate historical record. Do not overwrite previous visit content when the current task list changes.

### `Task`
- `id`, `siteId?`, `title`, `description?`, `status` (`OPEN`, `IN_PROGRESS`, `DONE`), `priority` (`LOW`, `NORMAL`, `HIGH`), optional `dueDate`, optional `completedAt`, `createdById`, optional `assigneeId`, `createdAt`, `updatedAt`.
- Indexes for open tasks by site/status and by assignee/status.
- Tasks are the current operational checklist; visit entries remain the historical log. Keep these responsibilities distinct.

### `VoiceSession` (metadata only)
- `id`, `userId`, `provider`, `modelId`, `status`, short `summary?`, optional transcript if retention is enabled, usage estimates, `startedAt`, `endedAt`.
- Do not store raw audio recordings by default.

### Other implementation details

- Add idempotency protection for create/update operations that may be retried after a timeout. A retry must not duplicate a visit or task.
- Use PostgreSQL transactions for operations that update a visit and multiple task records together.
- For dates, preserve local calendar dates in `Africa/Cairo`; do not let UTC conversion shift a visit into the previous/next day.
- `remainingWork` is a human-readable visit snapshot; the current open task list is the live operational state. The assistant may suggest task changes based on a visit but must show them separately for confirmation.
- Do not add finance/profit/pricing models in the MVP.

---

## 5. Neon hosting, environment setup, and backup

### Neon is the primary database host

- Create a Neon project for production and use its PostgreSQL connection details as secrets.
- Create a separate development branch/environment for schema changes and tests. Do not run experimental migrations directly on production.
- If Prisma 7 and the chosen driver support it, use a pooled Neon URL for normal runtime queries and a direct URL for migration commands.
- Keep `.env` out of Git. Commit only `.env.example` with empty values.

### Important backup distinction

Neon branches are useful for development/testing and short-lived recovery workflows, but **a second branch in the same project is not a complete independent backup**.

According to Neon's documentation checked on 26 October 2026, the Free plan includes **1 GB PostgreSQL storage per project, 100 CU-hours per project per month, 10 branches per project, one manual snapshot, and Instant Restore history limited to 6 hours and 1 GB of change history**. Quotas can change; recheck the account and official plan page before release. Instant Restore is not a long-term backup policy. If compute quota is exhausted, Neon can suspend the project until the quota resets or the plan changes.

Required backup approach:

1. Document Neon Instant Restore as the short-window recovery mechanism, not the only backup.
2. Add scripts/documentation for creating a PostgreSQL logical backup with `pg_dump` in a secure custom/compressed format, and restoring it with `pg_restore`.
3. Provide an export action for sites, visits, and tasks in an open format (JSON or CSV) so the client can retrieve data without relying on a vendor.
4. Keep a copy outside the production Neon project/account. The zero-cost MVP can start with an encrypted backup file stored on a user-controlled machine or existing free storage. Do not commit database dumps or secrets to Git.
5. Automated cloud backup is optional until a legitimate free destination/scheduler with suitable terms is chosen. Do not promise that cross-provider automated backups can remain free forever.
6. Test restore from a backup before calling the backup system complete.

Neon Free usage limits can cause the database compute to suspend after the current quota is consumed. Treat quota exhaustion as a recoverable service state: do not delete local data or mark pending sync as complete.

---

## 6. Offline-first behavior and syncing

Work sites may have weak mobile signal.

- Cache recently used sites, open tasks, and visit history in local SQLite.
- Allow the user to read cached records and prepare new visit/task drafts while offline.
- Mark offline writes as **Pending sync**. Push them when connectivity returns.
- Use a client-generated UUID `operationId` for each write; the server must handle replay idempotently.
- If a record changed on the server after the local copy was created, detect the conflict and ask the user to reload or reconcile. Do not silently overwrite another team member's update.
- Voice AI requires a working network unless a separate on-device model is explicitly implemented. Offline mode must preserve the text/structured draft and offer manual editing.
- Keep synchronization simple. No Redis, BullMQ, background queue service, or microservices for the MVP.

---

## 7. AI Voice Assistant — strict $0-first operation

### Primary: Gemini Live API, only after verification

Official documentation:
- https://ai.google.dev/gemini-api/docs/live
- https://ai.google.dev/gemini-api/docs/pricing
- https://ai.google.dev/gemini-api/docs/live-api/ephemeral-tokens
- https://ai.google.dev/gemini-api/docs/live-api/session-management

Before integration, recheck the current supported model ID, release state, Free Tier limits, Arabic/Egyptian dialect performance, data-use terms, commercial eligibility, session limits, and whether short-lived client credentials are supported for the selected flow.

- Never put the permanent AI-provider API key in the Flutter app.
- If supported by the current API, the backend creates a short-lived/ephemeral connection credential with limited permissions; Flutter connects using that credential.
- Enable session recovery/compaction only as described in the current official docs. A live audio session cannot be transferred seamlessly to another provider.
- Test real Egyptian Arabic phrases, site names, dates, numbers, camera counts, measurements, and noisy-site recordings before accepting the model.

### Free fallback chain

When Gemini Live hits its free limit or is unavailable, use a separate slower turn-based fallback **only if every selected fallback is still available under its free terms**:

1. Flutter records a short voice turn.
2. Speech-to-text provider transcribes it (compare Groq Whisper and Deepgram Nova-3 using the same Egyptian Arabic samples).
3. A text LLM interprets the request and returns a structured proposed action (test Gemini Flash and any independent free model that is currently available and permitted for the intended use).
4. Text-to-speech converts the reply into Arabic audio. **Build decision:** the
   Azure Speech path was removed because it requires a credit card. Replies are
   spoken by the device's built-in Arabic TTS, which costs nothing.
5. If any stage has exhausted its free quota, attempt another configured free provider once according to the router rules. Do not spin in a retry loop.

Do not hard-code model IDs or undocumented free-tier numbers. Keep providers configurable and update them after checking official docs. Do not use multiple keys in the same account/project to bypass a quota.

### Hard zero-cost rule

- `AI_ALLOW_PAID_FALLBACK=false` by default and `AI_MONTHLY_BUDGET_USD=0`.
- Do not enable provider billing, paid API calls, paid voice services, or an automatic upgrade without explicit approval.
- Track a rough usage estimate and show a graceful warning before the limit when possible.
- If every free provider is unavailable/over quota, stop AI calls, preserve the transcript/draft, and let the user continue manually. Never imply that the app has unlimited free voice conversations.
- Free-tier availability, commercial permissions, data-use terms, and quotas change. If a provider's current free terms are incompatible with the client’s business data or intended deployment, do not silently send sensitive data there; document the trade-off.

### Assistant behavior and tool/function calling

The assistant should sound natural and concise in Egyptian Arabic. Ask one question at a time and do not ask for data already present in the selected site/session.

Allowed server-side actions should be narrow and explicit, for example:
- `searchSites(query)`
- `getSiteSummary(siteId)`
- `listOpenTasks(siteId?)`
- `getVisitHistory(siteId, dateRange?)`
- `prepareVisitDraft(siteId, visitDate, completedWork, remainingWork, notes)`
- `prepareTaskDraft(siteId?, title, description, priority, dueDate?)`
- `prepareTaskUpdate(taskId, proposedChanges)`

The AI must never receive direct database credentials or issue SQL. The server validates every tool request and checks user/workspace permissions.

### Confirmation and factuality rules

- Reading a site's saved facts can happen after authorization.
- Any create/update/complete action becomes a draft first.
- The user must confirm a draft through a clear spoken confirmation or an explicit UI action before saving.
- Product/site names, site IDs, history, dates, current task status, and counts must be resolved from database records. The model must not invent missing facts.
- If the requested site is ambiguous, ask which one. If speech recognition is unsure about a critical number/date/site, read it back before confirmation.
- Use an idempotency ID on commit to avoid duplicate visits/tasks on reconnect.
- Do not retain raw audio by default. Transcript retention should be configurable and clearly described.

---

## 8. Backend API scope

Use REST endpoints under `/api/v1`. Keep routes small and consistent; return JSON errors in a common shape and validate every body/path/query.

Suggested endpoints:

- `POST /api/v1/auth/login`
- `POST /api/v1/auth/logout`
- `GET /api/v1/me`
- `GET /api/v1/workspaces`
- `POST /api/v1/workspaces/:id/invitations` (owner/admin only; if invitations are implemented in MVP)
- `GET /api/v1/sites?scope=personal|company`
- `POST /api/v1/sites`
- `GET /api/v1/sites/:id`
- `PATCH /api/v1/sites/:id`
- `GET /api/v1/sites/:id/visits`
- `POST /api/v1/sites/:id/visits`
- `PATCH /api/v1/visits/:id`
- `GET /api/v1/tasks?siteId=&status=`
- `POST /api/v1/tasks`
- `PATCH /api/v1/tasks/:id`
- `POST /api/v1/voice/session-credential` — authenticate and issue a short-lived provider credential if supported. Never return the permanent provider API key.
- `POST /api/v1/voice/fallback-turn` — accept a short audio turn, enforce file/size/duration limits, and do not retain the original recording by default.
- `GET /api/v1/voice/usage` — report estimates and configured limits.
- `GET /api/v1/export` — export authorized workspace/personal records in JSON or CSV.
- Sync endpoints may be added only if the chosen design needs them; avoid implementing duplicate sync mechanisms alongside ordinary idempotent resource endpoints.

Use TLS, precise CORS configuration, request size and rate limits, secure authentication/session handling, and redacted logs. Every record query must be scoped to the authenticated user or an authorized workspace.

---

## 9. Authentication and collaboration

- The user must be able to sign in on multiple devices and see synced records.
- Company sites need workspace membership so an authorized colleague can view open tasks and visit history after the client has moved on.
- Personal jobs remain private by default.
- Do not create open public sign-up by default. Start with a provisioned owner account and a controlled invitation flow for team members if collaboration is required in the first release.
- Use a currently maintained authentication implementation compatible with Flutter, Express, Prisma, and the selected deployment. Prefer standard secure sessions or short-lived access tokens with revocable refresh sessions; do not invent a custom password protocol.
- Store mobile credentials using platform secure storage, not shared preferences or plain local files.
- Every workspace action must enforce role permissions server-side. Guessing a UUID is not authorization.

---

## 10. Project structure

Suggested simple monorepo:

```text
job-manager/
  mobile/
    lib/
      app/
        app.dart
        router.dart
        theme.dart
      core/
        api/
        database/
        sync/
        audio/
        auth/
        errors/
      features/
        dashboard/
        sites/
        visits/
        tasks/
        voice_assistant/
        settings/
    test/
  server/
    src/
      app.ts
      server.ts
      config/
      db/
        prisma.ts
      middleware/
        auth.ts
        error-handler.ts
        rate-limit.ts
      modules/
        auth/
        workspaces/
        sites/
        visits/
        tasks/
        sync/
        export/
        voice/
          provider-router.ts
          gemini-live.ts
          fallback-pipeline.ts
          tool-actions.ts
      shared/
        validation/
        errors/
    prisma/
      schema.prisma
      migrations/
    tests/
    .env.example
  docs/
    DATABASE_BACKUP.md
    DEPLOYMENT.md
    AI_PROVIDER_NOTES.md
  README.md
```

The actual paths may be adjusted to match the repository, but keep the separation understandable. Do not create files/folders that are not needed by the actual code.

---

## 11. Environment variables

Illustrative names only. Never commit real values.

```dotenv
NODE_ENV=development
PORT=3000
DATABASE_URL=
DIRECT_URL=
AUTH_SECRET=
GEMINI_API_KEY=
GEMINI_LIVE_MODEL=
GROQ_API_KEY=
GROQ_STT_MODEL=
FALLBACK_LLM_PROVIDER=
FALLBACK_LLM_MODEL=
AI_MAX_SESSION_SECONDS=180
AI_MONTHLY_BUDGET_USD=0
AI_ALLOW_PAID_FALLBACK=false
TRANSCRIPT_RETENTION_ENABLED=false
```

- `DATABASE_URL` and `DIRECT_URL` naming must match the actual Prisma/Neon configuration. Use the pooled URL for runtime and the direct URL for migrations where required by the chosen driver.
- Use a secret manager/environment settings on the deployment host, not source files.
- When paid AI is disabled, paid calls must fail closed instead of being sent.
- If the selected provider requires billing to be enabled even for some requests, document that before enabling it. Do not activate billing automatically.

---

## 12. Testing and acceptance checklist

### Product and UI

- [ ] App builds on Android and is fully usable in Arabic RTL.
- [ ] The **My Jobs** and **Company Sites** sections are distinct and enforce their intended visibility.
- [ ] Create/edit/search site; view address/map link/general notes.
- [ ] Add multiple dated visits to one site and view history in correct local date order.
- [ ] Completed work, remaining work, and open tasks are not confused with one another.
- [ ] Authorized team members can see company-site updates from another account/device.
- [ ] Every voice workflow has a manual equivalent.
- [ ] Design is based on real data and avoids fake metrics/decorative AI elements.

### Database and sync

- [ ] Prisma migrations create the expected tables and indexes on Neon development branch.
- [ ] Production migrations are applied only after validation.
- [ ] Ownership/workspace authorization is tested for every read/write endpoint.
- [ ] Offline visits/tasks are preserved and synced after reconnect.
- [ ] Replayed operations do not create duplicate rows.
- [ ] Date-only visit entries do not shift due to UTC conversion.
- [ ] Backup export is created and a restore test succeeds.

### Voice and zero-cost operation

- [ ] Voice assistant understands a curated test set of Egyptian Arabic sentences, site names, dates, and counts.
- [ ] The assistant asks a targeted question for ambiguous sites or critical values.
- [ ] The assistant answers queries only from authorized saved data.
- [ ] Every write appears as a draft and requires confirmation.
- [ ] Gemini quota/service failure activates the fallback pipeline if a free fallback is available.
- [ ] If all free providers fail or run out of quota, the app preserves the draft and offers manual entry.
- [ ] No paid API request is made when `AI_ALLOW_PAID_FALLBACK=false`.
- [ ] No permanent API key is present in the app binary, logs, or client responses.
- [ ] No raw audio is stored by default.

### Quality

- [ ] TypeScript `7.0.2` type-check/build runs with the final package set; add tests for the Prisma/Neon adapter and provider router.
- [ ] Server validates requests and handles errors without exposing secrets or stack traces to users.
- [ ] No Prisma 8 RC or beta package has been introduced accidentally.
- [ ] No paid plan, billing upgrade, commercial API call, or automatic charge is enabled without explicit approval.

---

## 13. Build plan

### Phase 0 — verify versions and risks

- Verify current stable Flutter/Dart, `shadcn_ui`, Riverpod, TypeScript 7.0.2, Express 5, Prisma stable version, Node LTS, and Neon adapter compatibility.
- Confirm whether Prisma 8 is still RC. Use Prisma 7 stable unless Prisma 8 is GA and its compatibility/features are verified.
- Build a small compile/connectivity proof for TypeScript 7 + Express + Prisma + Neon before implementing business features.
- Test the audio capture/stream format and Egyptian Arabic Live API behavior in a separate prototype.

### Phase 1 — core app without AI

- Flutter UI, login, personal/company site separation, site details, tasks, visit history, search, and manual editing.
- Express API + Prisma + Neon PostgreSQL.
- Local SQLite caching, pending drafts, idempotent sync, and export/backup instructions.

### Phase 2 — primary voice assistant

- Add Gemini Live with the currently documented short-lived credential flow.
- Add structured assistant functions for querying sites and preparing visit/task drafts.
- Require confirmation before changes are committed.
- Test real Egyptian Arabic phrases and critical numeric/site-name accuracy.

### Phase 3 — free fallback + guardrails

- Add the STT → text LLM → TTS fallback only after verifying current free plans and commercial/data terms.
- Add error classification, limited retries, provider cool-down, usage estimates, and strict no-paid-call behavior.
- Add session summary/transcript recovery sufficient to resume after a provider switch.

### Phase 4 — release hardening

- Test offline sync conflicts, restore from export, role permissions, and security settings.
- Check deployment-provider free-plan terms and limits. No paid features may be enabled by default.
- Document exactly what works when free AI quotas are exhausted.

---

## 14. Non-goals for the MVP

- Pricing, purchasing cost, profit, invoicing, payroll, or accounting.
- MongoDB, Redis, BullMQ, Docker requirement, microservices, or a separate Python service.
- Unlimited-free AI claims.
- Keeping an open mic running in the background without a clear user action/consent.
- Automatic writes from AI without user confirmation.
- Site-photo cloud storage until a suitable free quota and data flow are verified.
- Building all fallback services before the primary voice loop and manual workflow work reliably.

---

## 15. Official references to recheck during implementation

### Flutter and UI

- Flutter SDK archive / stable channel: https://docs.flutter.dev/install/archive
- Flutter app architecture: https://docs.flutter.dev/app-architecture/recommendations
- Flutter offline-first guidance: https://docs.flutter.dev/app-architecture/design-patterns/offline-first
- `shadcn_ui` version/history: https://pub.dev/packages/shadcn_ui/versions
- `flutter_riverpod` versions: https://pub.dev/packages/flutter_riverpod
- SQLite/Drift: https://pub.dev/packages/drift and https://pub.dev/packages/sqflite
- Routing: https://pub.dev/packages/go_router

### Backend and versions

- TypeScript npm versions (TypeScript 7.0.2 checked as latest stable on 26 Oct 2026): https://www.npmjs.com/package/typescript
- TypeScript official blog: https://devblogs.microsoft.com/typescript/
- Node.js release schedule: https://nodejs.org/en/about/previous-releases
- Express: https://expressjs.com/
- Prisma ORM 7 docs: https://www.prisma.io/docs/orm/v7
- Prisma upgrade guide for v7: https://www.prisma.io/docs/guides/upgrade-prisma-orm/v7
- Prisma release status (check whether v8 is GA before choosing): https://www.prisma.io/docs/orm/release-status
- Prisma GitHub releases: https://github.com/prisma/orm/releases

### Neon and backup

- Neon connection guide: https://neon.com/docs/connect/connect-from-any-app
- Neon plan limits: https://neon.com/docs/introduction/plans
- Neon Free plan quota FAQ: https://neon.com/docs/introduction/free-tier
- Neon history window / Instant Restore: https://neon.com/docs/introduction/restore-window
- Prisma with Neon guide: https://www.prisma.io/docs/orm/v6/overview/databases/neon (legacy version link; use the matching current Prisma 7 or 8 docs for final configuration)

### AI providers

- Gemini Live API: https://ai.google.dev/gemini-api/docs/live
- Gemini pricing and Free Tier: https://ai.google.dev/gemini-api/docs/pricing
- Gemini ephemeral tokens: https://ai.google.dev/gemini-api/docs/live-api/ephemeral-tokens
- Gemini session management: https://ai.google.dev/gemini-api/docs/live-api/session-management
- Groq rate limits: https://console.groq.com/docs/rate-limits
- Groq speech-to-text: https://console.groq.com/docs/speech-to-text
- Deepgram Voice Agent / pricing: https://developers.deepgram.com/docs/voice-agent and https://deepgram.com/pricing

---

## Final instruction to the coding agent

Build the smallest complete and maintainable product that satisfies the client's actual workflow. Use **Flutter + shadcn_ui + Riverpod**, **Express 5 + TypeScript 7.0.2**, **Prisma**, and **Neon PostgreSQL**. Keep a clean architecture without unnecessary layers, keep the whole system at a strict $0 AI-spend ceiling by default, and preserve manual/offline workflows when providers or quotas fail. Use only verified compatible stable releases. Do not overbuild, silently change the stack, claim unlimited free usage, or mark the work complete until the acceptance checklist passes.
