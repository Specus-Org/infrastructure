---
status: pending
priority: p1
issue_id: "001"
tags: [code-review, security, postgresql]
dependencies: []
---

# Hardcoded Database Passwords in SQL Initialization Script

## Problem Statement

The PostgreSQL initialization scripts contain hardcoded placeholder passwords that will be committed to version control and potentially deployed to production.

**Why it matters:** If deployed without override, databases will have predictable credentials (`CHANGE_ME_VIA_ENV`) that attackers can easily guess. This is a critical security vulnerability.

## Findings

**File:** `postgres/init-scripts/02-schemas.sql`

| Line | Code | Issue |
|------|------|-------|
| 18 | `CREATE ROLE specus_app WITH LOGIN PASSWORD 'CHANGE_ME_VIA_ENV';` | Hardcoded placeholder |
| 31 | `CREATE ROLE airflow WITH LOGIN PASSWORD 'CHANGE_ME_VIA_ENV';` | Hardcoded placeholder |

The comment says "remember to change the password" but there's no mechanism to enforce this. SQL scripts cannot read environment variables directly.

## Proposed Solutions

### Option A: Entrypoint Script with Environment Variables (Recommended)
Create a shell wrapper that substitutes environment variables before running SQL.

**Pros:** Secure, follows 12-factor app principles
**Cons:** Adds a script layer
**Effort:** Small
**Risk:** Low

```bash
#!/bin/bash
# /docker-entrypoint-initdb.d/00-setup-passwords.sh
psql -U postgres <<EOF
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'airflow') THEN
        CREATE ROLE airflow WITH LOGIN PASSWORD '${AIRFLOW_DB_PASSWORD}';
    END IF;
END
\$\$;
EOF
```

### Option B: Remove User Creation from Init Scripts
Let applications create their own database users via migrations or external provisioning.

**Pros:** Simplest, follows YAGNI
**Cons:** Requires external user management
**Effort:** Small
**Risk:** Low

### Option C: Use Docker Secrets
Mount passwords as Docker secrets and read them in init scripts.

**Pros:** Most secure for production
**Cons:** More complex Docker setup
**Effort:** Medium
**Risk:** Low

## Recommended Action

<!-- Fill during triage -->

## Technical Details

**Affected files:**
- `postgres/init-scripts/02-schemas.sql`

**Components:** PostgreSQL initialization

## Acceptance Criteria

- [ ] No hardcoded passwords in any SQL files
- [ ] Passwords sourced from environment variables or secrets
- [ ] Init scripts work with dynamic password injection
- [ ] Documentation updated with password configuration

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-03 | Created from code review | SQL cannot read env vars directly |

## Resources

- [PostgreSQL Docker Environment Variables](https://hub.docker.com/_/postgres)
- [Docker Secrets](https://docs.docker.com/engine/swarm/secrets/)
