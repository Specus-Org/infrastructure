---
status: pending
priority: p3
issue_id: "015"
tags: [code-review, simplification, airflow, yagni]
dependencies: []
---

# Unused Airflow Configuration Sections

## Problem Statement

The Airflow configuration includes commented-out sections for features not being used (Celery, email, SMTP, metrics).

**Why it matters:** Placeholder configuration adds noise and can be confusing. Airflow's documentation is the authoritative source for these settings.

## Findings

**File:** `airflow/airflow.cfg`

| Lines | Section | Issue |
|-------|---------|-------|
| 118-120 | `[celery]` | Not used with LocalExecutor |
| 122-130 | `[email]` and `[smtp]` | Commented placeholder |
| 146-151 | `[metrics]` StatsD | Commented placeholder |

**Reduction:** ~35 lines

## Proposed Solutions

### Option A: Remove Placeholder Sections (Recommended)
Delete commented-out sections entirely.

**Pros:** Cleaner, less noise
**Cons:** Must look up docs when needed
**Effort:** Small
**Risk:** Low

### Option B: Keep for Reference
Document that these are intentionally disabled.

**Pros:** Quick reference
**Cons:** More to maintain
**Effort:** None
**Risk:** None

## Recommended Action

<!-- Fill during triage -->

## Technical Details

**Affected files:**
- `airflow/airflow.cfg`

**Components:** Airflow configuration

## Acceptance Criteria

- [ ] Unused sections removed
- [ ] Config file is more focused
- [ ] Airflow still works correctly

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-03 | Created from code review | Official docs are better reference |

## Resources

- [Airflow Configuration Reference](https://airflow.apache.org/docs/apache-airflow/stable/configurations-ref.html)
