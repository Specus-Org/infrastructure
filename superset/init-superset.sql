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

-- =============================================================================
-- STEP 1: Run while connected to 'postgres' database
-- =============================================================================

-- Create the Superset metadata database
CREATE DATABASE superset;

-- Create the dedicated Superset user
CREATE USER superset_user WITH ENCRYPTED PASSWORD 'CHANGE_ME_SECURE_PASSWORD';

-- Grant database ownership
GRANT ALL PRIVILEGES ON DATABASE superset TO superset_user;

-- =============================================================================
-- STEP 2: Run while connected to 'superset' database
-- =============================================================================

-- Grant schema privileges so Superset can create and manage its own tables
GRANT ALL ON SCHEMA public TO superset_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO superset_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO superset_user;
