-- Authentik Database Initialization
-- Run this manually via DBeaver or any SQL client
--
-- Instructions:
--   1. Replace 'CHANGE_ME_SECURE_PASSWORD' with your actual password
--   2. Run Step 1 first (connected to postgres database)
--   3. Then connect to 'authentik' database and run Step 2

-- =============================================================================
-- STEP 1: Run while connected to 'postgres' database
-- =============================================================================

-- Create database
CREATE DATABASE authentik;

-- Create user
CREATE USER authentik_user WITH ENCRYPTED PASSWORD 'CHANGE_ME_SECURE_PASSWORD';

-- Grant database privileges
GRANT ALL PRIVILEGES ON DATABASE authentik TO authentik_user;

-- =============================================================================
-- STEP 2: Run while connected to 'authentik' database
-- =============================================================================

-- Grant schema privileges
GRANT ALL ON SCHEMA public TO authentik_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO authentik_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO authentik_user;
