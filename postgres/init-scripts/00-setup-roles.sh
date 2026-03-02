#!/bin/bash
# =============================================================================
# PostgreSQL Role Setup Script
# =============================================================================
# Creates database roles with passwords from environment variables.
# This script runs before SQL init scripts and allows secure password injection.
#
# Environment Variables:
#   SPECUS_APP_PASSWORD - Password for specus_app role (required for production)
#   AIRFLOW_DB_PASSWORD - Password for airflow role (required for production)
#
# If passwords are not set, random passwords are generated (for development only).
# =============================================================================

set -e

# Function to generate a random password
generate_random_password() {
    openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32
}

# Get passwords from environment variables or generate random ones
if [ -z "$SPECUS_APP_PASSWORD" ]; then
    SPECUS_APP_PASSWORD=$(generate_random_password)
    echo "WARNING: SPECUS_APP_PASSWORD not set. Generated random password."
    echo "WARNING: For production, set SPECUS_APP_PASSWORD environment variable."
fi

if [ -z "$AIRFLOW_DB_PASSWORD" ]; then
    AIRFLOW_DB_PASSWORD=$(generate_random_password)
    echo "WARNING: AIRFLOW_DB_PASSWORD not set. Generated random password."
    echo "WARNING: For production, set AIRFLOW_DB_PASSWORD environment variable."
fi

echo "Setting up database roles..."

# Create roles with passwords from environment variables
# Passwords are passed as psql variables (-v) to avoid shell interpolation
# in SQL. The heredoc delimiter is quoted ('EOSQL') to prevent any shell
# expansion. Inside PL/pgSQL DO blocks, psql :'var' syntax is unavailable,
# so passwords are passed via custom GUC parameters and retrieved with
# current_setting(), then safely interpolated using format(%L).
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    -v specus_pw="$SPECUS_APP_PASSWORD" \
    -v airflow_pw="$AIRFLOW_DB_PASSWORD" \
    <<-'EOSQL'
    -- Inject passwords into session-level GUC parameters so they are
    -- accessible inside DO blocks via current_setting().
    SELECT set_config('specus.app_password', :'specus_pw', false);
    SELECT set_config('specus.airflow_password', :'airflow_pw', false);

    -- Create specus_app role if it doesn't exist
    DO $$
    DECLARE
        _pw text := current_setting('specus.app_password');
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'specus_app') THEN
            EXECUTE format('CREATE ROLE specus_app WITH LOGIN PASSWORD %L', _pw);
            RAISE NOTICE 'Created specus_app role with secure password.';
        ELSE
            EXECUTE format('ALTER ROLE specus_app WITH PASSWORD %L', _pw);
            RAISE NOTICE 'Updated specus_app role password.';
        END IF;
    END
    $$;

    -- Create airflow role if it doesn't exist
    DO $$
    DECLARE
        _pw text := current_setting('specus.airflow_password');
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'airflow') THEN
            EXECUTE format('CREATE ROLE airflow WITH LOGIN PASSWORD %L', _pw);
            RAISE NOTICE 'Created airflow role with secure password.';
        ELSE
            EXECUTE format('ALTER ROLE airflow WITH PASSWORD %L', _pw);
            RAISE NOTICE 'Updated airflow role password.';
        END IF;
    END
    $$;

    -- Clear passwords from session GUC parameters
    SELECT set_config('specus.app_password', '', false);
    SELECT set_config('specus.airflow_password', '', false);
EOSQL

echo "Database roles setup complete."
