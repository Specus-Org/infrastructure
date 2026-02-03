---
status: pending
priority: p2
issue_id: "006"
tags: [code-review, performance, postgresql, memory]
dependencies: []
---

# PostgreSQL Memory Settings Suboptimal for 4GB Server

## Problem Statement

PostgreSQL memory settings are too conservative, leaving performance on the table, while work_mem could cause issues under high concurrency.

**Why it matters:** Underutilized shared_buffers means more disk I/O. Overly high work_mem combined with many connections could exhaust memory.

## Findings

**File:** `postgres/postgresql.conf`

| Line | Setting | Current | Recommended | Issue |
|------|---------|---------|-------------|-------|
| 20 | `shared_buffers` | 256MB | 1GB | Only 6% of RAM (should be 25%) |
| 26 | `work_mem` | 16MB | 8MB | Risk of OOM under concurrency |
| 29 | `effective_cache_size` | 768MB | 3GB | Planner underestimates cache |

**Impact:**
- Low `shared_buffers`: More disk reads, slower queries
- Low `effective_cache_size`: Suboptimal query plans (avoids index scans)
- High `work_mem`: 100 connections × 16MB × 4 operations = 6.4GB potential

## Proposed Solutions

### Option A: Tune for 4GB Dedicated Database (Recommended)

```ini
shared_buffers = 1GB           # 25% of RAM
effective_cache_size = 3GB     # 75% of RAM
work_mem = 8MB                 # Safer for concurrency
maintenance_work_mem = 256MB   # For VACUUM, CREATE INDEX
```

**Pros:** Optimal for dedicated DB server
**Cons:** Assumes PostgreSQL is primary workload
**Effort:** Small
**Risk:** Low

### Option B: Keep Conservative for Shared Server
If PostgreSQL shares resources with Airflow on same host.

**Pros:** Safer memory sharing
**Cons:** Lower performance
**Effort:** None
**Risk:** None

## Recommended Action

<!-- Fill during triage -->

## Technical Details

**Affected files:**
- `postgres/postgresql.conf`

**Components:** PostgreSQL memory management

## Acceptance Criteria

- [ ] Memory settings match deployment architecture
- [ ] README documents memory allocation strategy
- [ ] Configuration comments updated with rationale

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-03 | Created from code review | shared_buffers should be ~25% for dedicated DB |

## Resources

- [PostgreSQL Tuning Guide](https://wiki.postgresql.org/wiki/Tuning_Your_PostgreSQL_Server)
- [PGTune](https://pgtune.leopard.in.ua/)
