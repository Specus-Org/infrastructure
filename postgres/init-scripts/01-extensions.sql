-- =============================================================================
-- Specus PostgreSQL Extensions Initialization
-- =============================================================================
-- This script creates all required extensions for the Specus platform.
-- Extensions are created in $POSTGRES_DB (specus by default).
-- pg_cron requires cron.database_name in postgresql.conf to match this database.
-- =============================================================================

-- Enable pg_stat_statements for query performance monitoring
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Enable uuid-ossp for UUID generation (uuid_generate_v4, etc.)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable pg_trgm for fuzzy text search and similarity matching
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Enable pg_cron for in-database job scheduling
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Enable ParadeDB pg_search for BM25 full-text search
CREATE EXTENSION IF NOT EXISTS pg_search;

-- Enable Apache AGE for graph database functionality
CREATE EXTENSION IF NOT EXISTS age;

-- Load AGE into the search path for the current session
-- Note: Applications using AGE should set this at connection time
LOAD 'age';
SET search_path = ag_catalog, "$user", public;

-- =============================================================================
-- Verification: List all installed extensions
-- =============================================================================
SELECT
    e.extname AS "Extension",
    e.extversion AS "Version",
    n.nspname AS "Schema",
    c.description AS "Description"
FROM pg_extension e
LEFT JOIN pg_namespace n ON n.oid = e.extnamespace
LEFT JOIN pg_description c ON c.objoid = e.oid AND c.classoid = 'pg_extension'::regclass
ORDER BY e.extname;
