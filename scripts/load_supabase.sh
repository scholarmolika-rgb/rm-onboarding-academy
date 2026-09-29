#!/usr/bin/env bash
# Load the RM Onboarding Academy into a Supabase project in one go:
#   1. apply every migration in supabase/migrations/ that is not applied yet
#      (recorded in supabase_migrations.schema_migrations, the same table the Supabase CLI uses)
#   2. upload the CSV files in supabase/csv/ in the right order, then run after_import.sql
#      (skipped automatically if the data is already there, so running twice is safe)
#
# Usage (repository root):
#   SUPABASE_DB_URL="postgresql://postgres.<ref>:<password>@aws-0-ap-south-1.pooler.supabase.com:5432/postgres" \
#   INCLUDE_DEMO_JOINEES=false  bash scripts/load_supabase.sh
# Normally run by GitHub Actions: .github/workflows/load-supabase.yml
set -euo pipefail

: "${SUPABASE_DB_URL:?Set SUPABASE_DB_URL to your Supabase connection string (Session pooler, port 5432)}"
INCLUDE_DEMO_JOINEES="${INCLUDE_DEMO_JOINEES:-false}"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-supabase/migrations}"
PSQL=(psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -q -X)

echo "== Checking the connection"
"${PSQL[@]}" -At -c "select 'Connected to ' || current_database() || ' as ' || current_user"

echo "== 1. Migrations"
"${PSQL[@]}" -c "create schema if not exists supabase_migrations;
  create table if not exists supabase_migrations.schema_migrations(version text primary key, statements text[], name text);"
shopt -s nullglob
files=("$MIGRATIONS_DIR"/*.sql)
if [ ${#files[@]} -eq 0 ]; then
  echo "No migration files found in $MIGRATIONS_DIR. Run this from the repository root." >&2; exit 1
fi
for f in "${files[@]}"; do            # globs sort by name, so migrations run in number order
  base=$(basename "$f" .sql); version="${base%%_*}"; name="${base#*_}"
  applied=$("${PSQL[@]}" -At -c "select count(*) from supabase_migrations.schema_migrations where version = '$version'")
  if [ "$applied" = "1" ]; then echo "   skip  $base (already applied)"; continue; fi
  echo "   apply $base"
  # each migration runs in one transaction together with its tracking row
  { echo "begin;"; cat "$f"; echo;
    echo "insert into supabase_migrations.schema_migrations(version, name) values ('$version', '$name');"
    echo "commit;"; } | "${PSQL[@]}"
done

echo "== 2. CSV data"
has_data=$("${PSQL[@]}" -At -c "select count(*) > 0 from cohorts")
if [ "$has_data" = "t" ]; then
  echo "   Data already loaded (cohorts has rows). Nothing uploaded. Delete the rows first to reload."
else
  "${PSQL[@]}" -v include_demo="$INCLUDE_DEMO_JOINEES" -f supabase/csv/import_all.sql
fi

echo "== 3. Summary"
"${PSQL[@]}" -c "select role, count(*) as people from profiles group by role order by role;"
"${PSQL[@]}" -c "select name, capacity, used, free from v_seat_usage;"
echo "Done. Next: create the HR partners' first logins (docs/SUPABASE_SETUP_GUIDE.md, Step 7)."
