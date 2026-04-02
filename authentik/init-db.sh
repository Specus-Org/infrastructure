#!/bin/bash
# =============================================================================
# Authentik PostgreSQL Database Initialization
# =============================================================================
# Creates the authentik role and database with ownership transfer.
# Authentik's Django migrations require full schema control, so the role
# must OWN the database (not just have privileges).
#
# Run once against the PostgreSQL container:
#   docker exec -i specus-postgres bash < authentik/init-db.sh
#
# Or with a custom password:
#   docker exec -e AUTHENTIK_DB_PASSWORD="mypass" -i specus-postgres \
#     bash < authentik/init-db.sh
#
# Environment Variables:
#   AUTHENTIK_DB_PASSWORD - Password for authentik role (required for production)
#   POSTGRES_USER        - PostgreSQL superuser (default: postgres)
#
# If AUTHENTIK_DB_PASSWORD is not set, a random password is generated.
# =============================================================================

set -e

# Default superuser
POSTGRES_USER="${POSTGRES_USER:-postgres}"

# Generate random password if not provided
if [ -z "$AUTHENTIK_DB_PASSWORD" ]; then
    AUTHENTIK_DB_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
    echo "WARNING: AUTHENTIK_DB_PASSWORD not set. Generated random password."
    echo "Generated password: $AUTHENTIK_DB_PASSWORD"
    echo "Save this password — it will not be shown again."
fi

echo "Setting up Authentik database..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" \
    -v authentik_pw="$AUTHENTIK_DB_PASSWORD" \
    <<-'EOSQL'
    -- Inject password into session-level GUC parameter
    SELECT set_config('specus.authentik_password', :'authentik_pw', false);

    -- Create authentik role if it doesn't exist
    DO $$
    DECLARE
        _pw text := current_setting('specus.authentik_password');
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authentik') THEN
            EXECUTE format('CREATE ROLE authentik WITH LOGIN PASSWORD %L', _pw);
            RAISE NOTICE 'Created authentik role.';
        ELSE
            EXECUTE format('ALTER ROLE authentik WITH PASSWORD %L', _pw);
            RAISE NOTICE 'Updated authentik role password.';
        END IF;
    END
    $$;

    -- Create authentik database if it doesn't exist
    SELECT 'CREATE DATABASE authentik'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'authentik')\gexec

    -- Transfer ownership so Authentik can manage its own schema migrations
    DO $$
    BEGIN
        IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'authentik') THEN
            EXECUTE 'ALTER DATABASE authentik OWNER TO authentik';
            RAISE NOTICE 'Transferred authentik database ownership.';
        END IF;
    END
    $$;

    -- Clear password from session GUC parameter
    SELECT set_config('specus.authentik_password', '', false);
EOSQL

echo "Authentik database setup complete."
echo "Connection string: postgresql://authentik:<password>@specus-postgres:5432/authentik"
