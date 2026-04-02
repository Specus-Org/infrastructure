-- =============================================================================
-- Specus PostgreSQL Schema Setup (Minimal)
-- =============================================================================
-- Creates Airflow and Authentik databases. Application-specific schemas should
-- be created by the respective services when needed.
-- =============================================================================

-- Create Airflow database if it doesn't exist
SELECT 'CREATE DATABASE airflow'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'airflow')\gexec

-- Grant permissions (airflow role is created by 00-setup-roles.sh)
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'airflow') THEN
        GRANT ALL PRIVILEGES ON DATABASE airflow TO airflow;
    END IF;
END
$$;

-- =============================================================================
-- Create Authentik database with ownership transfer
-- =============================================================================
-- Authentik runs Django migrations that require full schema control (CREATE,
-- ALTER, DROP on tables/sequences/indexes). Ownership grants this implicitly.
-- =============================================================================

SELECT 'CREATE DATABASE authentik'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'authentik')\gexec

-- Transfer ownership so Authentik can manage its own schema migrations
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'authentik') THEN
        EXECUTE 'ALTER DATABASE authentik OWNER TO authentik';
    END IF;
END
$$;

-- =============================================================================
-- Grant specus_app access to the specus database
-- =============================================================================
-- specus_app is the application role used by backend services.
-- Grants are applied via \gexec to target the specus database context.
-- =============================================================================

-- Grant connect privilege on the specus database
SELECT 'GRANT CONNECT ON DATABASE ' || datname || ' TO specus_app'
FROM pg_database WHERE datname = 'specus'\gexec

-- Switch to the specus database for schema-level grants
\c specus

DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'specus_app') THEN
        -- Schema usage
        GRANT USAGE ON SCHEMA public TO specus_app;

        -- DML on all existing tables
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO specus_app;

        -- Sequence access for serial/identity columns
        GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO specus_app;

        -- Ensure future tables/sequences are also accessible
        ALTER DEFAULT PRIVILEGES IN SCHEMA public
            GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO specus_app;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public
            GRANT USAGE, SELECT ON SEQUENCES TO specus_app;
    END IF;
END
$$;

-- Switch back to the default database
\c postgres

SELECT 'PostgreSQL initialization complete!' AS status;
