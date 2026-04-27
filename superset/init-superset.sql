-- Superset Metadata Database Initialization
-- Run this manually via DBeaver or any SQL client
--
-- Instructions:
--   1. Replace 'CHANGE_ME_SECURE_PASSWORD' with the password you set in .env
--      (SUPERSET_DB_PASSWORD)
--   2. Run Step 1 while connected to the 'postgres' database
--   3. Then connect to the 'superset' database and run Step 2
--
-- This script is safe to run once. Running Step 1 a second time will fail
-- with "already exists" errors — that is expected and harmless.
--
-- DO NOT ADD `IF NOT EXISTS` to CREATE USER or CREATE DATABASE below.
-- Idempotency here is a footgun: on re-run, an IF-NOT-EXISTS CREATE USER
-- silently skips the password update while the rest of the script runs,
-- leaving the DB role and .env out of sync. Let the loud failure stand.

-- =============================================================================
-- STEP 1: Run while connected to 'postgres' database
-- =============================================================================

-- Create the Superset metadata database
CREATE DATABASE superset;

-- Create the dedicated Superset user
CREATE USER superset_user WITH ENCRYPTED PASSWORD 'CHANGE_ME_SECURE_PASSWORD';

-- Transfer ownership of the superset database so superset_user can run
-- migrations, REINDEX, ALTER, etc. without needing the postgres superuser.
ALTER DATABASE superset OWNER TO superset_user;

-- Least-privilege isolation: prevent superset_user from connecting to other
-- databases in this cluster (notably 'postgres', 'airflow', 'authentik').
REVOKE CONNECT ON DATABASE postgres FROM superset_user;

-- =============================================================================
-- STEP 2: Run while connected to 'superset' database
-- =============================================================================

-- As owner, superset_user has full control of the public schema and all
-- objects it creates. No additional grants required.
--
-- If you ever run migrations as a different role (e.g. postgres superuser),
-- uncomment the block below to grant superset_user access to future tables:
--
-- GRANT ALL ON SCHEMA public TO superset_user;
-- ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO superset_user;
-- ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO superset_user;
