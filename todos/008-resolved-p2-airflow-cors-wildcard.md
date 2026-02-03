---
status: pending
priority: p2
issue_id: "008"
tags: [code-review, security, airflow, api]
dependencies: []
---

# Wildcard CORS Configuration in Airflow API

## Problem Statement

The Airflow API is configured to accept requests from any origin (`*`), which could enable CSRF attacks.

**Why it matters:** Any website can make authenticated requests to the Airflow API if a user has an active session, potentially allowing malicious sites to trigger DAGs or access sensitive information.

## Findings

**File:** `airflow/airflow.cfg`

| Line | Setting | Value | Issue |
|------|---------|-------|-------|
| 140 | `access_control_allow_origins` | `*` | Allows all origins |

## Proposed Solutions

### Option A: Restrict to Known Origins (Recommended)
Specify the actual domains that need API access.

**Pros:** Secure
**Cons:** Requires knowing deployment domain upfront
**Effort:** Small
**Risk:** Low

```ini
access_control_allow_origins = https://airflow.yourdomain.com
```

### Option B: Use Environment Variable
Allow configuration at deployment time.

**Pros:** Flexible
**Cons:** Requires documentation
**Effort:** Small
**Risk:** Low

```ini
# Set via AIRFLOW__API__ACCESS_CONTROL_ALLOW_ORIGINS
```

## Recommended Action

<!-- Fill during triage -->

## Technical Details

**Affected files:**
- `airflow/airflow.cfg`

**Components:** Airflow REST API

## Acceptance Criteria

- [ ] CORS origins restricted or configurable
- [ ] README documents CORS configuration

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-03 | Created from code review | CORS protects against cross-site request forgery |

## Resources

- [Airflow API Security](https://airflow.apache.org/docs/apache-airflow/stable/security/api.html)
