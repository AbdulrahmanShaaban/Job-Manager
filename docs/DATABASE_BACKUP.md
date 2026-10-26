# Database backup and restore

Neon is the only database. This document defines the backup policy, the exact
commands, and the restore drill.

> **Nothing here has been executed against a real Neon database.** `bash`,
> `pg_dump`, and `pg_restore` are not installed on the build machine, so the
> scripts were reviewed by hand and never run. Your first action after reading
> this must be a restore drill into a throwaway Neon branch.

---

## 1. What Neon gives you, and what it does not

Neon Instant Restore is a **short-window** recovery mechanism: as checked on
26 October 2026, the Free plan limited it to roughly 6 hours of history and 1 GB
of change history. It cannot recover a table dropped three weeks ago, and it
lives inside the same Neon account.

Therefore:

| Mechanism | Recovers from | Not sufficient for |
| --- | --- | --- |
| Neon Instant Restore | Recent bad deploy, accidental delete within hours | Long-term retention, account loss, billing lockout |
| Neon branch in the same project | Schema experiments, restore drills | Independent backup — shares project storage and quota |
| `pg_dump` logical backup **outside** Neon | Account loss, long-term retention, migration between providers | Point-in-time recovery between dumps |
| In-app JSON/CSV export | Vendor-independent copy of business records | Restoring relations, sessions, or invariants |

The supported policy is: **logical dump outside the account, on a schedule you
actually keep, plus a tested restore.**

---

## 2. Retention and schedule (zero-cost MVP)

A realistic $0 policy for a small team:

| Item | Value |
| --- | --- |
| Full logical dump | Weekly, plus before every migration or destructive change |
| Retention | Keep the last 8 weekly dumps and the last 3 pre-migration dumps |
| Location | An encrypted folder on a user-controlled machine, or existing free storage the client already pays for |
| Encryption | Whole-disk or archive encryption (e.g. `age`, `gpg`, or an encrypted volume). Never plain files on a shared drive. |
| Off-site copy | At least one copy on a different provider/account than Neon |
| Restore drill | Once per quarter, into a throwaway Neon branch |

Do not promise that cross-provider automated backups will remain free forever.
Automated cloud scheduling is optional and out of scope until a destination with
acceptable terms is chosen.

---

## 3. Taking a backup

`server/scripts/backup.sh` uses the **direct** connection (`DIRECT_URL`), not the
pooled one, and writes a PostgreSQL custom-format archive (`-Fc`, gzip level 9)
with owners and privileges stripped so it restores anywhere.

```bash
cd server
./scripts/backup.sh /secure/backups
# or
BACKUP_DIR=/secure/backups npm run backup
```

What the script does:

1. Refuses to run if `pg_dump` is missing.
2. Reads `DIRECT_URL` from the environment, or parses only that line out of
   `server/.env` (it does not `source` the file).
3. Refuses to write inside the repository — dumps contain client data.
4. Creates `job-manager-<UTC timestamp>.dump`.
5. Fails if the file is empty.
6. Verifies the archive with `pg_restore --list`.
7. Writes a `.sha256` sidecar when `sha256sum` is available.

Afterwards, copy the dump and its checksum to encrypted storage outside the Neon
account. Record the date, size, and checksum somewhere durable.

### Why `--no-owner --no-privileges`

Neon role names differ between projects and branches. Stripping ownership makes
the dump restorable into a fresh branch, a local PostgreSQL instance, or another
provider without a role-mapping step.

---

## 4. Restoring

`server/scripts/restore.sh` takes the dump and an **explicit target URL**. It
never reads the target from the environment, so a production restore cannot
happen because a variable was left set.

```bash
cd server
./scripts/restore.sh /secure/backups/job-manager-20261101T020000Z.dump \
  'postgresql://...throwaway-branch...?sslmode=require'
```

What the script does:

1. Validates that the file is a readable custom-format archive.
2. Verifies the `.sha256` sidecar when present; aborts on mismatch.
3. Prints the target with the password masked.
4. Requires you to type `restore` unless `--yes` is passed.
5. Runs `pg_restore --clean --if-exists --no-owner --no-privileges
   --single-transaction --exit-on-error`.
6. Fails loudly on a non-zero exit instead of pretending success.

`--clean --if-exists` makes the restore repeatable but **destructive**: objects
present in the target and in the dump are dropped and recreated. Anything in the
target that is *not* in the dump is left alone.

### Restore order of operations

1. Restore into a throwaway Neon branch first. Always.
2. Verify (see section 5).
3. Only then consider production. Before a production restore, take a fresh dump
   of production — even a broken database is evidence.
4. If the API is running, stop it or put it in maintenance mode. A restore
   inside `--single-transaction` is atomic, but clients mid-request will see
   errors either way.

---

## 5. Restore verification checklist

Run all of these against the restored branch:

1. Row counts are plausible:
   ```sql
   SELECT 'User', count(*) FROM "User"
   UNION ALL SELECT 'Workspace', count(*) FROM "Workspace"
   UNION ALL SELECT 'WorkspaceMember', count(*) FROM "WorkspaceMember"
   UNION ALL SELECT 'Site', count(*) FROM "Site"
   UNION ALL SELECT 'Visit', count(*) FROM "Visit"
   UNION ALL SELECT 'Task', count(*) FROM "Task"
   UNION ALL SELECT 'Session', count(*) FROM "Session";
   ```
2. Point the API at the restored branch and `GET /health` → 200.
3. `POST /api/v1/auth/login` with a known account succeeds.
4. `GET /api/v1/sites?scope=company` returns the expected sites.
5. Open one site: visit history is ordered newest-first and open task counts are
   correct.
6. `GET /api/v1/export?format=json` returns the same site/visit/task counts.
7. Write one visit and one task, then re-read them — the restored schema accepts
   writes (sequences and defaults survived).
8. Only after all seven pass: record "restore drill passed on <date>".

If step 1 or 7 fails, the dump is incomplete. Do not overwrite the previous good
dump.

---

## 6. Export as a complementary path

The API exposes `GET /api/v1/export`:

- `format=json` returns the **full** authorized dataset — sites with nested
  visits and tasks, plus personal tasks, workspaces, and the exporting user. The
  `entity` parameter is ignored for JSON on purpose: a partial JSON export is a
  worse recovery artifact than a complete one.
- `format=csv&entity=sites|visits|tasks` returns one flat table with a UTF-8 BOM
  so Arabic opens correctly in Excel. `entity` defaults to `sites`.

The Settings screen can write these files to the device's application documents
directory as `job-manager-<entity>-<timestamp>.<json|csv>`.

This is not a database backup: it cannot restore sessions, invitations, voice
session usage, or foreign keys. It is the answer to "the client wants their data
without depending on a vendor".

---

## 7. What not to do

- Do not commit a `.dump`, `.sql` export, or `.env` to source control. The
  repository has no VCS today; if you add one, add these to `.gitignore` first.
- Do not treat a second Neon branch as an independent backup.
- Do not run `prisma migrate dev` or `prisma migrate reset` against production.
- Do not "fix" a suspended Neon project by clearing the mobile outbox or
  deleting local SQLite data.
- Do not store dumps unencrypted on a shared or cloud-synced folder.
- Do not delete the last known-good dump before a restore drill passes.
