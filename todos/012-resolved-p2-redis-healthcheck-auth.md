---
status: pending
priority: p2
issue_id: "012"
tags: [code-review, architecture, redis, docker]
dependencies: []
---

# Redis Healthcheck Does Not Support Password Authentication

## Problem Statement

The Redis Dockerfile healthcheck uses `redis-cli ping` without authentication, but Redis is configured to require a password at runtime. This causes false healthcheck failures.

**Why it matters:** Container orchestrators will report the container as unhealthy even when Redis is working correctly.

## Findings

**File:** `redis/Dockerfile`

| Line | Code | Issue |
|------|------|-------|
| 16 | `CMD redis-cli ping \| grep -q PONG` | No password provided |

When `--requirepass` is set via command override, this healthcheck returns:
```
(error) NOAUTH Authentication required.
```

## Proposed Solutions

### Option A: Use Environment Variable in Healthcheck (Recommended)

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD redis-cli -a "${REDIS_PASSWORD:-}" ping 2>/dev/null | grep -q PONG || exit 1
```

**Pros:** Works with or without password
**Cons:** Password visible in environment
**Effort:** Small
**Risk:** Low

### Option B: Use REDISCLI_AUTH Environment Variable

```dockerfile
ENV REDISCLI_AUTH=""
HEALTHCHECK ... CMD redis-cli ping | grep -q PONG || exit 1
```

**Pros:** Cleaner, no `-a` flag
**Cons:** Requires env var to be set
**Effort:** Small
**Risk:** Low

## Recommended Action

<!-- Fill during triage -->

## Technical Details

**Affected files:**
- `redis/Dockerfile`

**Components:** Redis, Docker healthcheck

## Acceptance Criteria

- [ ] Healthcheck works with password authentication
- [ ] Healthcheck works without password (development)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-03 | Created from code review | REDISCLI_AUTH env var available |

## Resources

- [Redis CLI Authentication](https://redis.io/docs/connect/cli/)
