#!/bin/bash
# Strivo - Database Migration Runner
# Applies SQL migrations in order to your Supabase database
#
# Usage:
#   ./supabase/migrate.sh              # Apply all pending migrations
#   ./supabase/migrate.sh --dry-run    # Preview without applying
#
# Required environment variables:
#   SUPABASE_DB_HOST     - Database host (e.g., db.lqcurwdwuxperyzbfgyk.supabase.co)
#   SUPABASE_DB_PORT     - Database port (default: 5432)
#   SUPABASE_DB_NAME     - Database name (default: postgres)
#   SUPABASE_DB_USER     - Database user (default: postgres)
#   SUPABASE_DB_PASSWORD - Database password

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MIGRATIONS_DIR="$SCRIPT_DIR/migrations"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check required env vars
: "${SUPABASE_DB_HOST:?Set SUPABASE_DB_HOST}"
: "${SUPABASE_DB_PASSWORD:?Set SUPABASE_DB_PASSWORD}"

DB_PORT="${SUPABASE_DB_PORT:-5432}"
DB_NAME="${SUPABASE_DB_NAME:-postgres}"
DB_USER="${SUPABASE_DB_USER:-postgres}"
DRY_RUN="${1:-}"

echo "========================================="
echo "  Strivo Database Migration Runner"
echo "========================================="
echo "Host:     $SUPABASE_DB_HOST"
echo "Port:     $DB_PORT"
echo "Database: $DB_NAME"
echo "User:     $DB_USER"
echo "Migrations: $MIGRATIONS_DIR"
echo "========================================="

# Check psql is available
if ! command -v psql &> /dev/null; then
  echo -e "${RED}Error: psql not found. Install PostgreSQL client.${NC}"
  exit 1
fi

# Create schema history table if not exists
psql -h "$SUPABASE_DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
  -c "CREATE TABLE IF NOT EXISTS schema_migrations (
    version text PRIMARY KEY,
    applied_at timestamptz NOT NULL DEFAULT now()
  );" > /dev/null

# Get applied migrations
APPLIED=$(psql -h "$SUPABASE_DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
  -t -A -c "SELECT version FROM schema_migrations ORDER BY version;")

# Apply migrations in order
for f in "$MIGRATIONS_DIR"/V*.sql; do
  filename=$(basename "$f")
  version="${filename%%__*}"

  if echo "$APPLIED" | grep -q "^$version$"; then
    echo -e "${YELLOW}  SKIP${NC}  $filename (already applied)"
    continue
  fi

  if [ "$DRY_RUN" = "--dry-run" ]; then
    echo -e "${GREEN}  WOULD APPLY${NC}  $filename"
    continue
  fi

  echo -e "${GREEN}  APPLYING${NC}  $filename..."
  psql -h "$SUPABASE_DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -v ON_ERROR_STOP=1 -f "$f" > /dev/null

  psql -h "$SUPABASE_DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -c "INSERT INTO schema_migrations (version) VALUES ('$version');" > /dev/null

  echo -e "${GREEN}  DONE${NC}  $filename"
done

echo "========================================="
echo -e "${GREEN}All migrations complete!${NC}"
echo "========================================="
