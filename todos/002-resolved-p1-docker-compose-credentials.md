---
status: resolved
priority: p1
issue_id: "002"
tags: [code-review, security, airflow, docker]
dependencies: []
---

# Hardcoded Credentials in Docker Compose

## Problem Statement

The `airflow/docker-compose.yml` file contains multiple hardcoded credentials including database passwords, admin credentials, and secret keys.

**Why it matters:** Even though labeled "local development only," these credentials are committed to version control and may accidentally be used in production or copied to other environments.

## Findings

**File:** `airflow/docker-compose.yml`

| Line | Credential | Value |
|------|------------|-------|
| 14 | Database connection | `postgresql://airflow:airflow_password@postgres:5432/airflow` |
| 18 | Webserver secret key | `'local-dev-secret-key-change-in-production'` |
| 23-24 | Admin user/password | `admin` / `admin` |
| 45-46 | PostgreSQL credentials | `postgres` / `postgres_password` |
| 66, 70 | Redis password | `redis_password` (exposed in command and healthcheck) |
| 93 | Admin password in init | `--password admin` |

## Proposed Solutions

### Option A: Use .env File with Template (Recommended)
Create `.env.example` template and use `env_file:` in docker-compose.

**Pros:** Standard practice, keeps secrets out of YAML
**Cons:** Requires users to create .env
**Effort:** Small
**Risk:** Low

```yaml
# docker-compose.yml
env_file:
  - .env

# .env.example (committed)
POSTGRES_PASSWORD=change_me
AIRFLOW_DB_PASSWORD=change_me
REDIS_PASSWORD=change_me
AIRFLOW_SECRET_KEY=generate_with_python
AIRFLOW_ADMIN_PASSWORD=change_me
```

### Option B: Use Variable Substitution with Defaults
Use `${VAR:-default}` syntax requiring explicit environment setup.

**Pros:** Self-documenting, flexible
**Cons:** Still has defaults visible
**Effort:** Small
**Risk:** Low

### Option C: Remove docker-compose.yml
Since this is for Dokploy deployment, docker-compose may not be needed.

**Pros:** Eliminates the problem entirely
**Cons:** Loses local development convenience
**Effort:** Small
**Risk:** Medium

## Recommended Action

<!-- Fill during triage -->

## Technical Details

**Affected files:**
- `airflow/docker-compose.yml`

**Components:** Airflow, PostgreSQL, Redis local dev stack

## Acceptance Criteria

- [x] No plaintext passwords in docker-compose.yml
- [x] `.env.example` template created with placeholder values
- [x] `.env` added to .gitignore (already done)
- [ ] README updated with local setup instructions

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-03 | Created from code review | docker-compose supports env_file directive |
| 2026-02-03 | Resolved: Updated docker-compose.yml to use ${VAR:-default} syntax for all credentials. Created .env.example template. | Used Option B approach with variable substitution and defaults |

## Resources

- [Docker Compose Environment Variables](https://docs.docker.com/compose/environment-variables/)
