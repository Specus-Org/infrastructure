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
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create specus_app role if it doesn't exist
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'specus_app') THEN
            CREATE ROLE specus_app WITH LOGIN PASSWORD '$SPECUS_APP_PASSWORD';
            RAISE NOTICE 'Created specus_app role with secure password.';
        ELSE
            -- Update password if role already exists
            ALTER ROLE specus_app WITH PASSWORD '$SPECUS_APP_PASSWORD';
            RAISE NOTICE 'Updated specus_app role password.';
        END IF;
    END
    \$\$;

    -- Create airflow role if it doesn't exist
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'airflow') THEN
            CREATE ROLE airflow WITH LOGIN PASSWORD '$AIRFLOW_DB_PASSWORD';
            RAISE NOTICE 'Created airflow role with secure password.';
        ELSE
            -- Update password if role already exists
            ALTER ROLE airflow WITH PASSWORD '$AIRFLOW_DB_PASSWORD';
            RAISE NOTICE 'Updated airflow role password.';
        END IF;
    END
    \$\$;
EOSQL

echo "Database roles setup complete."
