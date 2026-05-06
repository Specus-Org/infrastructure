#!/bin/bash
# =============================================================================
# Superset Read-Only Role Setup
# =============================================================================
# Creates the database role Superset uses to query the Specus application
# database as a BI data source. This is separate from superset_user, which owns
# Superset's metadata database.
#
# Environment Variables:
#   SUPERSET_READONLY_PASSWORD - Password for superset_readonly role
# =============================================================================

set -e

generate_random_password() {
    openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32
}

if [ -z "$SUPERSET_READONLY_PASSWORD" ]; then
    SUPERSET_READONLY_PASSWORD=$(generate_random_password)
    echo "WARNING: SUPERSET_READONLY_PASSWORD not set. Generated random password."
    echo "WARNING: Set SUPERSET_READONLY_PASSWORD in production so the Superset"
    echo "WARNING: database connection password is known to operators."
fi

echo "Setting up Superset read-only database role..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" \
    -v superset_readonly_pw="$SUPERSET_READONLY_PASSWORD" \
    <<-'EOSQL'
    DO $$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'superset_readonly') THEN
            CREATE ROLE superset_readonly WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
            RAISE NOTICE 'Created superset_readonly role.';
        ELSE
            RAISE NOTICE 'Updated superset_readonly role password.';
        END IF;
    END
    $$;

    ALTER ROLE superset_readonly WITH PASSWORD :'superset_readonly_pw';
    ALTER ROLE superset_readonly SET default_transaction_read_only = on;
    ALTER ROLE superset_readonly SET statement_timeout = '300s';
    GRANT CONNECT ON DATABASE specus TO superset_readonly;
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "specus" <<-'EOSQL'
    GRANT USAGE ON SCHEMA public TO superset_readonly;
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO superset_readonly;

    -- Future tables created by the postgres superuser or app role should remain
    -- visible in Superset without manually revisiting grants after each deploy.
    ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
        GRANT SELECT ON TABLES TO superset_readonly;

    DO $$
    BEGIN
        IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'specus_app') THEN
            ALTER DEFAULT PRIVILEGES FOR ROLE specus_app IN SCHEMA public
                GRANT SELECT ON TABLES TO superset_readonly;
        END IF;
    END
    $$;
EOSQL

echo "Superset read-only database role setup complete."
