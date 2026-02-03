---
status: pending
priority: p3
issue_id: "016"
tags: [code-review, simplification, airflow, docker]
dependencies: []
---

# Unnecessary Redis in Airflow Docker Compose

## Problem Statement

The Airflow docker-compose.yml includes Redis as a dependency, but LocalExecutor does not use Redis. This adds unnecessary complexity and resource usage.

**Why it matters:** Extra services consume resources and add potential failure points. Redis is only needed for CeleryExecutor.

## Findings

**File:** `airflow/docker-compose.yml`

| Lines | Code | Issue |
|-------|------|-------|
| 33-34 | `redis: condition: service_healthy` | Unnecessary dependency |
| 59-74 | Redis service definition | Not used by LocalExecutor |

## Proposed Solutions

### Option A: Remove Redis Entirely (Recommended)
Delete Redis service and dependency from docker-compose.

**Pros:** Simpler, faster startup, less resources
**Cons:** Must add back if switching to CeleryExecutor
**Effort:** Small
**Risk:** Low

### Option B: Make Redis Optional
Use docker-compose profiles to optionally include Redis.

**Pros:** Flexible
**Cons:** More complex
**Effort:** Medium
**Risk:** Low

## Recommended Action

<!-- Fill during triage -->

## Technical Details

**Affected files:**
- `airflow/docker-compose.yml`

**Components:** Airflow local development stack

## Acceptance Criteria

- [ ] Redis removed from docker-compose
- [ ] Airflow still starts and works
- [ ] Faster local development startup

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-03 | Created from code review | LocalExecutor uses database, not Redis |

## Resources

- [Airflow Executors](https://airflow.apache.org/docs/apache-airflow/stable/executor/index.html)
