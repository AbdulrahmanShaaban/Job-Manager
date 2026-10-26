#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Job Manager — PostgreSQL logical backup (pg_dump custom/compressed format).
#
# Usage:
#   ./scripts/backup.sh <output-directory>
#   BACKUP_DIR=/secure/backups ./scripts/backup.sh
#
# The output directory MUST be outside this repository. Dumps contain client
# data and must never be committed to Git or stored in the Neon project.
# ---------------------------------------------------------------------------
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
server_dir="$(cd "${script_dir}/.." && pwd)"
repo_dir="$(cd "${server_dir}/.." && pwd)"

die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

command -v pg_dump >/dev/null 2>&1 || die "pg_dump not found. Install the PostgreSQL client tools (version >= the server's major version)."

# --- Load DIRECT_URL from server/.env unless already exported --------------
if [[ -z "${DIRECT_URL:-}" && -f "${server_dir}/.env" ]]; then
  # Read only the DIRECT_URL line; do not source the file (values may contain
  # characters that are unsafe to eval).
  while IFS= read -r line || [[ -n "${line}" ]]; do
    case "${line}" in
      DIRECT_URL=*)
        value="${line#DIRECT_URL=}"
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"
        DIRECT_URL="${value}"
        ;;
    esac
  done < "${server_dir}/.env"
fi

[[ -n "${DIRECT_URL:-}" ]] || die "DIRECT_URL is not set. Export it or add it to server/.env (use the direct, non-pooled Neon endpoint)."

# --- Resolve output directory ---------------------------------------------
backup_dir="${1:-${BACKUP_DIR:-}}"
[[ -n "${backup_dir}" ]] || die "No output directory. Pass one as \$1 or set BACKUP_DIR."

mkdir -p "${backup_dir}"
backup_dir="$(cd "${backup_dir}" && pwd)"

case "${backup_dir}/" in
  "${repo_dir}/"*)
    die "Refusing to write a database dump inside the repository (${repo_dir}). Choose a directory outside it."
    ;;
esac

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
target="${backup_dir}/job-manager-${timestamp}.dump"

# --- Dump ------------------------------------------------------------------
printf 'Backing up to %s\n' "${target}"

# --no-owner / --no-privileges keeps the dump portable between Neon branches
# and local PostgreSQL instances. Never echo the connection string.
pg_dump \
  --dbname="${DIRECT_URL}" \
  --format=custom \
  --compress=9 \
  --no-owner \
  --no-privileges \
  --file="${target}"

[[ -s "${target}" ]] || die "pg_dump produced an empty file."

# --- Verify the archive is readable ---------------------------------------
pg_restore --list "${target}" >/dev/null || die "Backup archive failed verification (pg_restore --list)."

size="$(wc -c < "${target}" | tr -d '[:space:]')"
printf 'OK: %s (%s bytes)\n' "${target}" "${size}"

# --- Optional checksum sidecar --------------------------------------------
if command -v sha256sum >/dev/null 2>&1; then
  ( cd "${backup_dir}" && sha256sum "$(basename "${target}")" > "$(basename "${target}").sha256" )
  printf 'Checksum: %s.sha256\n' "${target}"
fi

cat <<'EOF'

Next steps:
  1. Copy the dump to encrypted storage outside the Neon account (user-controlled
     machine or existing free storage). Do not commit it to Git.
  2. Test the restore at least once:
       ./scripts/restore.sh <dump-file> <throwaway-database-url>
  3. Record the backup date and restore-test result in your operations notes.
EOF
