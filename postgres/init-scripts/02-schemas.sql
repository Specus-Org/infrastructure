-- =============================================================================
-- Specus PostgreSQL Schema Setup (Minimal)
-- =============================================================================
-- Creates only the Airflow database. Application-specific schemas should be
-- created by the respective services when needed.
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

SELECT 'PostgreSQL initialization complete!' AS status;
