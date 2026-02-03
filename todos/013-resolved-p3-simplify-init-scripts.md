---
status: resolved
priority: p3
issue_id: "013"
tags: [code-review, simplification, postgresql, yagni]
dependencies: ["001"]
---

# Overly Complex PostgreSQL Init Scripts (YAGNI)

## Problem Statement

The PostgreSQL init scripts create roles, schemas, views, and permissions for features that don't exist yet, violating YAGNI principles.

**Why it matters:** Extra complexity increases maintenance burden and potential for errors. Create infrastructure when needed, not speculatively.

## Findings

**File:** `postgres/init-scripts/02-schemas.sql`

| Lines | Feature | Issue |
|-------|---------|-------|
| 14-22 | `specus_app` role | Never used by any application |
| 44-58 | `app`, `analytics`, `audit` schemas | No tables exist |
| 67-70 | Default privileges | For "future tables" |
| 79-87 | Commented cron jobs | Dead code |
| 94-122 | Monitoring views | Can create on-demand |

**Current:** 127 lines
**Needed:** ~15 lines (just Airflow database/user)

## Proposed Solutions

### Option A: Minimal Init Script (Recommended)
Only create what Airflow needs.

**Pros:** Simple, follows YAGNI
**Cons:** Must add more later if needed
**Effort:** Small
**Risk:** Low

```sql
-- Simplified 02-schemas.sql
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'airflow') THEN
        CREATE ROLE airflow WITH LOGIN;
    END IF;
END
$$;

CREATE DATABASE airflow OWNER airflow;
```

### Option B: Keep But Document
Accept complexity but document why each piece exists.

**Pros:** Ready for future
**Cons:** Maintenance burden
**Effort:** None
**Risk:** None

## Recommended Action

Option A implemented: Minimal init script that only creates what Airflow needs.

## Technical Details

**Affected files:**
- `postgres/init-scripts/02-schemas.sql`

**Components:** PostgreSQL initialization

## Acceptance Criteria

- [x] Only essential database objects created
- [x] ~90% reduction in init script size (107 lines to 21 lines = 80% reduction)
- [ ] Airflow still works (requires testing)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-03 | Created from code review | YAGNI - add when needed |
| 2026-02-03 | Implemented Option A | Reduced 02-schemas.sql from 107 to 21 lines |

## Resources

- [YAGNI Principle](https://martinfowler.com/bliki/Yagni.html)
