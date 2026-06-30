-- Umami Database Initialization
-- Run this on core PostgreSQL before deploying Umami.
--
-- Usage:
--   read -rsp "Umami DB password: " UMAMI_DB_PASSWORD; printf '\n'
--   { printf "\\set umami_password '%s'\n" "$UMAMI_DB_PASSWORD"; cat init-umami.sql; } \
--     | psql -U postgres -d postgres
--   unset UMAMI_DB_PASSWORD
--
-- The database is UTF8 encoded. Umami runs Prisma migrations on first start;
-- umami_user owns the database so those migrations can create tables.

\set ON_ERROR_STOP on

\if :{?umami_password}
\else
  \echo 'ERROR: set umami_password before running init-umami.sql'
  \quit 1
\endif

-- =============================================================================
-- STEP 1: Run while connected to the postgres maintenance database
-- =============================================================================

SELECT format('CREATE ROLE umami_user LOGIN ENCRYPTED PASSWORD %L', :'umami_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'umami_user')
\gexec

SELECT format('ALTER ROLE umami_user WITH LOGIN ENCRYPTED PASSWORD %L', :'umami_password')
WHERE EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'umami_user')
\gexec

SELECT 'CREATE DATABASE umami WITH OWNER umami_user ENCODING ''UTF8'' TEMPLATE template0'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'umami')
\gexec

DO $$
DECLARE
  umami_encoding text;
BEGIN
  SELECT pg_encoding_to_char(encoding)
  INTO umami_encoding
  FROM pg_database
  WHERE datname = 'umami';

  IF umami_encoding IS DISTINCT FROM 'UTF8' THEN
    RAISE EXCEPTION 'database umami must use UTF8 encoding, found %', umami_encoding;
  END IF;
END
$$;

ALTER DATABASE umami OWNER TO umami_user;
GRANT ALL PRIVILEGES ON DATABASE umami TO umami_user;

-- Tenant isolation: remove the broad PUBLIC connect grant so other tenant
-- roles cannot reach the umami database.
REVOKE CONNECT ON DATABASE umami FROM PUBLIC;

-- =============================================================================
-- STEP 2: Connect to umami and grant schema privileges
-- =============================================================================

\connect umami

GRANT USAGE, CREATE ON SCHEMA public TO umami_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO umami_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO umami_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO umami_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO umami_user;
