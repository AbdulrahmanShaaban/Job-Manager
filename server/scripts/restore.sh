#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Job Manager — restore a pg_dump custom-format backup.
#
# Usage:
#   ./scripts/restore.sh <dump-file> <target-database-url> [--yes]
#
# The target URL is required explicitly so a production restore is never a
# side effect of a missing environment variable. DESTRUCTIVE: the script
# drops and recreates every object contained in the dump.
#
# Recommended practice: restore into a throwaway Neon branch or a local
# PostgreSQL database first, verify the row counts, then restore production.
# ---------------------------------------------------------------------------
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

dump_file="${1:-}"
target_url="${2:-}"
assume_yes="${3:-}"

[[ -n "${dump_file}" ]] || die "Usage: restore.sh <dump-file> <target-database-url> [--yes]"
[[ -n "${target_url}" ]] || die "Usage: restore.sh <dump-file> <target-database-url> [--yes]"
[[ -f "${dump_file}" ]] || die "Dump file not found: ${dump_file}"

command -v pg_restore >/dev/null 2>&1 || die "pg_restore not found. Install the PostgreSQL client tools."

# --- Verify the archive before touching the target -------------------------
pg_restore --list "${dump_file}" >/dev/null || die "Not a valid pg_dump custom-format archive: ${dump_file}"

# --- Optional checksum check ----------------------------------------------
checksum_file="${dump_file}.sha256"
if [[ -f "${checksum_file}" ]] && command -v sha256sum >/dev/null 2>&1; then
  printf 'Verifying checksum...\n'
  ( cd "$(dirname "${dump_file}")" && sha256sum --check --status "$(basename "${checksum_file}")" ) \
    || die "Checksum mismatch. The dump file may be corrupted or truncated."
  printf 'Checksum OK.\n'
fi

# --- Confirmation gate -----------------------------------------------------
# Print only the host/database portion, never the password.
safe_target="$(printf '%s' "${target_url}" | sed -E 's#(://)[^@/]*@#\1***@#')"

printf '\nThis will DROP and recreate objects in:\n  %s\n' "${safe_target}"
printf 'From backup:\n  %s\n\n' "${dump_file}"

if [[ "${assume_yes}" != "--yes" ]]; then
  printf 'Type "restore" to continue: '
  read -r confirmation
  [[ "${confirmation}" == "restore" ]] || die "Aborted."
fi

# --- Restore ---------------------------------------------------------------
# --clean --if-exists drops existing objects first so the restore is
# repeatable. --no-owner/--no-privileges keeps roles portable.
set +e
pg_restore \
  --dbname="${target_url}" \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  --single-transaction \
  --exit-on-error \
  --verbose \
  "${dump_file}"
status=$?
set -e

if [[ ${status} -ne 0 ]]; then
  die "pg_restore failed with exit code ${status}. The target may be partially restored; inspect the output above."
fi

printf '\nRestore complete.\n'
cat <<'EOF'

Verify before trusting the restore:
  1. Start the API against the restored database and call GET /api/v1/me.
  2. Check row counts for Site, Visit, Task, User, Workspace, Session.
  3. Open a site, its visit history, and its open tasks in the app.
  4. Sign in with a known account (sessions restore too, but re-login is safer).
EOF
