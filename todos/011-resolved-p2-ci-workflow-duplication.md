---
status: pending
priority: p2
issue_id: "011"
tags: [code-review, architecture, ci-cd, dry]
dependencies: []
---

# Duplicate CI/CD Workflow Logic

## Problem Statement

All three GitHub Actions workflows are 95% identical, violating DRY principles and increasing maintenance burden.

**Why it matters:** Any change to build logic must be replicated across 3 files, increasing chance of inconsistency.

## Findings

**Files:**
- `.github/workflows/build-postgres.yml`
- `.github/workflows/build-redis.yml`
- `.github/workflows/build-airflow.yml`

**Differences between files:**
| Variable | postgres | redis | airflow |
|----------|----------|-------|---------|
| IMAGE_NAME | specus-postgres | specus-redis | specus-airflow |
| context | ./postgres | ./redis | ./airflow |
| tags | 17 | 7 | 2.10 |

Everything else is identical (~80 lines duplicated).

## Proposed Solutions

### Option A: Reusable Workflow (Recommended)
Create a callable workflow that accepts parameters.

**Pros:** Single source of truth, DRY
**Cons:** Slightly more complex
**Effort:** Medium
**Risk:** Low

```yaml
# .github/workflows/build-image.yml
on:
  workflow_call:
    inputs:
      image_name:
        required: true
        type: string
      context:
        required: true
        type: string
      version_tag:
        required: true
        type: string

# .github/workflows/build-postgres.yml
jobs:
  build:
    uses: ./.github/workflows/build-image.yml
    with:
      image_name: specus-postgres
      context: ./postgres
      version_tag: "17"
```

### Option B: Matrix Strategy
Use matrix to build all images in one workflow.

**Pros:** Single file
**Cons:** Less flexible triggers per service
**Effort:** Medium
**Risk:** Low

## Recommended Action

<!-- Fill during triage -->

## Technical Details

**Affected files:**
- All `.github/workflows/build-*.yml` files

**Components:** CI/CD

## Acceptance Criteria

- [ ] Common logic in reusable workflow
- [ ] Service-specific workflows call reusable workflow
- [ ] Path-based triggers still work

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-03 | Created from code review | GHA supports workflow_call |

## Resources

- [Reusing Workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows)
