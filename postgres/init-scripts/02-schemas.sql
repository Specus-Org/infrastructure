-- =============================================================================
-- Specus PostgreSQL Schema Setup
-- =============================================================================
-- Creates the base schema structure and common configurations.
-- Application-specific schemas should be created by the respective services.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Create application user (password should be set via environment variable)
-- -----------------------------------------------------------------------------
-- Note: The actual password is set via POSTGRES_PASSWORD environment variable
-- This creates an additional application user for non-superuser access

DO $$
BEGIN
    -- Create specus_app role if it doesn't exist
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'specus_app') THEN
        CREATE ROLE specus_app WITH LOGIN PASSWORD 'CHANGE_ME_VIA_ENV';
        RAISE NOTICE 'Created specus_app role. Remember to change the password!';
    END IF;
END
$$;

-- -----------------------------------------------------------------------------
-- Create Airflow database and user
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    -- Create airflow role if it doesn't exist
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'airflow') THEN
        CREATE ROLE airflow WITH LOGIN PASSWORD 'CHANGE_ME_VIA_ENV';
        RAISE NOTICE 'Created airflow role. Remember to change the password!';
    END IF;
END
$$;

-- Create airflow database if it doesn't exist
SELECT 'CREATE DATABASE airflow OWNER airflow'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'airflow')\gexec

-- Grant necessary permissions to airflow user
GRANT ALL PRIVILEGES ON DATABASE airflow TO airflow;

-- -----------------------------------------------------------------------------
-- Create base schemas in the default database
-- -----------------------------------------------------------------------------

-- Schema for application data
CREATE SCHEMA IF NOT EXISTS app;
COMMENT ON SCHEMA app IS 'Primary application data schema';

-- Schema for analytics and reporting
CREATE SCHEMA IF NOT EXISTS analytics;
COMMENT ON SCHEMA analytics IS 'Analytics, aggregations, and reporting data';

-- Schema for audit logs
CREATE SCHEMA IF NOT EXISTS audit;
COMMENT ON SCHEMA audit IS 'Audit trail and change history';

-- -----------------------------------------------------------------------------
-- Grant schema permissions
-- -----------------------------------------------------------------------------
GRANT USAGE ON SCHEMA app TO specus_app;
GRANT USAGE ON SCHEMA analytics TO specus_app;
GRANT USAGE ON SCHEMA audit TO specus_app;

-- Grant table permissions (for future tables)
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO specus_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA analytics GRANT SELECT ON TABLES TO specus_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA audit GRANT SELECT, INSERT ON TABLES TO specus_app;

-- -----------------------------------------------------------------------------
-- Create AGE graph (example - applications should create their own)
-- -----------------------------------------------------------------------------
-- Uncomment if you want a default graph
-- SELECT create_graph('specus_graph');

-- -----------------------------------------------------------------------------
-- pg_cron: Example scheduled jobs
-- -----------------------------------------------------------------------------
-- These are examples - uncomment and modify as needed

-- Clean up old pg_stat_statements data weekly
-- SELECT cron.schedule('reset-pg-stat-statements', '0 3 * * 0', 'SELECT pg_stat_statements_reset()');

-- Vacuum analyze daily at 2 AM UTC
-- SELECT cron.schedule('daily-vacuum', '0 2 * * *', 'VACUUM ANALYZE');

-- -----------------------------------------------------------------------------
-- Useful views for monitoring
-- -----------------------------------------------------------------------------

-- View for monitoring slow queries (from pg_stat_statements)
CREATE OR REPLACE VIEW public.slow_queries AS
SELECT
    calls,
    round(total_exec_time::numeric, 2) AS total_time_ms,
    round(mean_exec_time::numeric, 2) AS avg_time_ms,
    round(max_exec_time::numeric, 2) AS max_time_ms,
    rows,
    query
FROM pg_stat_statements
WHERE mean_exec_time > 100  -- queries averaging over 100ms
ORDER BY mean_exec_time DESC
LIMIT 50;

COMMENT ON VIEW public.slow_queries IS 'Top 50 slowest queries by average execution time';

-- View for database size monitoring
CREATE OR REPLACE VIEW public.database_sizes AS
SELECT
    datname AS database_name,
    pg_size_pretty(pg_database_size(datname)) AS size
FROM pg_database
WHERE datistemplate = false
ORDER BY pg_database_size(datname) DESC;

COMMENT ON VIEW public.database_sizes IS 'Database sizes in human-readable format';

-- Grant read access to monitoring views
GRANT SELECT ON public.slow_queries TO specus_app;
GRANT SELECT ON public.database_sizes TO specus_app;

-- =============================================================================
-- Initialization Complete
-- =============================================================================
SELECT 'PostgreSQL initialization complete!' AS status;
