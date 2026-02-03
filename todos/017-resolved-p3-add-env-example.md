---
status: pending
priority: p3
issue_id: "017"
tags: [code-review, documentation, security]
dependencies: ["001", "002", "003"]
---

# Missing .env.example Template

## Problem Statement

There's no `.env.example` file to document required environment variables, making it unclear what secrets need to be configured.

**Why it matters:** New developers and operators need clear guidance on required configuration.

## Findings

Required environment variables are scattered across:
- README.md (Dokploy deployment section)
- docker-compose.yml (hardcoded values)
- airflow.cfg (comments about env vars)

## Proposed Solutions

### Option A: Create .env.example (Recommended)

```bash
# .env.example
# PostgreSQL
POSTGRES_PASSWORD=generate_secure_password
POSTGRES_USER=postgres
POSTGRES_DB=specus

# Airflow
AIRFLOW_DB_PASSWORD=generate_secure_password
AIRFLOW__CORE__FERNET_KEY=generate_with_python
AIRFLOW__WEBSERVER__SECRET_KEY=generate_hex_string
AIRFLOW_ADMIN_PASSWORD=generate_secure_password

# Redis
REDIS_PASSWORD=generate_secure_password
```

**Pros:** Clear, self-documenting
**Cons:** Must maintain
**Effort:** Small
**Risk:** Low

## Recommended Action

<!-- Fill during triage -->

## Technical Details

**New file:** `.env.example` or `airflow/.env.example`

**Components:** Documentation, configuration

## Acceptance Criteria

- [ ] .env.example created with all required variables
- [ ] Comments explain how to generate each secret
- [ ] README references .env.example

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-03 | Created from code review | .env.example is standard practice |

## Resources

- [12-Factor App Config](https://12factor.net/config)
