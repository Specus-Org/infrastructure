---
status: pending
priority: p2
issue_id: "005"
tags: [code-review, performance, airflow, memory]
dependencies: []
---

# Airflow Parallelism Too High for 4GB Server

## Problem Statement

Airflow is configured to run 16 parallel tasks, but on a 4GB server this will cause out-of-memory (OOM) conditions.

**Why it matters:** With LocalExecutor, each task runs as a subprocess consuming 100-500MB. 16 parallel tasks plus scheduler and webserver will exceed 4GB RAM, causing system instability or crashes.

## Findings

**File:** `airflow/airflow.cfg`

| Line | Setting | Value | Issue |
|------|---------|-------|-------|
| 18 | `parallelism` | 16 | Too high |
| 21 | `max_active_tasks_per_dag` | 8 | Too high |
| 24 | `max_active_runs_per_dag` | 4 | Acceptable |

**Memory calculation (worst case):**
- Airflow webserver: ~500MB
- Airflow scheduler: ~300MB
- 16 task processes × 200MB: ~3.2GB
- PostgreSQL: ~1.5GB
- **Total: ~5.5GB** (exceeds 4GB)

## Proposed Solutions

### Option A: Reduce to 4 Parallel Tasks (Recommended)
Set conservative limits matching available resources.

**Pros:** Prevents OOM, stable operation
**Cons:** Lower throughput
**Effort:** Small
**Risk:** Low

```ini
parallelism = 4
max_active_tasks_per_dag = 4
max_active_runs_per_dag = 2
```

### Option B: Make Configurable via Environment
Allow runtime tuning based on deployment size.

**Pros:** Flexible
**Cons:** Requires documentation
**Effort:** Small
**Risk:** Low

## Recommended Action

<!-- Fill during triage -->

## Technical Details

**Affected files:**
- `airflow/airflow.cfg`

**Components:** Airflow scheduler, task execution

## Acceptance Criteria

- [ ] Parallelism reduced to safe value for 4GB server
- [ ] Documentation updated with resource requirements
- [ ] Memory calculations added to README

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-03 | Created from code review | LocalExecutor spawns subprocesses per task |

## Resources

- [Airflow Configuration Reference](https://airflow.apache.org/docs/apache-airflow/stable/configurations-ref.html)
