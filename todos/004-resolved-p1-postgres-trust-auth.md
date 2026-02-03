---
status: resolved
priority: p1
issue_id: "004"
tags: [code-review, security, postgresql, authentication]
dependencies: []
---

# PostgreSQL Superuser Trust Authentication

## Problem Statement

The PostgreSQL superuser (`postgres`) is configured with `trust` authentication for local Unix socket connections, meaning any process inside the container can connect as superuser without a password.

**Why it matters:** If an attacker gains any level of container access (e.g., through a vulnerable application), they immediately have full database superuser privileges without needing to crack any passwords.

## Findings

**File:** `postgres/pg_hba.conf`

| Line | Configuration |
|------|---------------|
| 8 | `local   all   postgres   trust` |

This bypasses all authentication for the most privileged database user when connecting via Unix socket.

## Proposed Solutions

### Option A: Use scram-sha-256 for All Users (Recommended)
Remove trust authentication entirely.

**Pros:** Consistent security model
**Cons:** Requires password for all local operations
**Effort:** Small
**Risk:** Low

```
# pg_hba.conf
local   all             postgres                                scram-sha-256
local   all             all                                     scram-sha-256
```

### Option B: Use peer Authentication
Map Unix user to PostgreSQL user (more secure than trust).

**Pros:** No password needed, still authenticated
**Cons:** Requires Unix user matching
**Effort:** Small
**Risk:** Low

```
local   all             postgres                                peer
```

### Option C: Keep Trust but Document Risk
Accept the risk for containerized environments.

**Pros:** Simpler operations
**Cons:** Security risk remains
**Effort:** None
**Risk:** High

## Recommended Action

<!-- Fill during triage -->

## Technical Details

**Affected files:**
- `postgres/pg_hba.conf`

**Components:** PostgreSQL authentication

## Acceptance Criteria

- [x] No `trust` authentication for any user
- [x] `POSTGRES_PASSWORD` environment variable documented as required
- [x] Init scripts work with password authentication
- [x] Healthcheck updated if needed

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-03 | Created from code review | Docker postgres image sets POSTGRES_PASSWORD |
| 2026-02-03 | Resolved: Changed postgres user auth from trust to scram-sha-256 | Consistent security model for all users |

## Resources

- [PostgreSQL pg_hba.conf Documentation](https://www.postgresql.org/docs/current/auth-pg-hba-conf.html)
