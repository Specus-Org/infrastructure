---
status: pending
priority: p2
issue_id: "009"
tags: [code-review, performance, docker, airflow]
dependencies: []
---

# build-essential Remains in Final Airflow Image

## Problem Statement

The Airflow Dockerfile installs `build-essential` (gcc, g++, make, etc.) which adds ~200MB to the final image, but it's not needed since `psycopg2-binary` is precompiled.

**Why it matters:** Larger images mean slower pulls, more storage, and increased attack surface.

## Findings

**File:** `airflow/Dockerfile`

| Line | Code | Issue |
|------|------|-------|
| 17-21 | `apt-get install ... build-essential` | Not needed for precompiled packages |
| 32 | `psycopg2-binary` | Already precompiled, no compilation needed |

## Proposed Solutions

### Option A: Remove build-essential (Recommended)
Keep only `libpq-dev` for psycopg2-binary runtime.

**Pros:** ~200MB smaller image
**Cons:** Cannot compile Python packages
**Effort:** Small
**Risk:** Low

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
```

### Option B: Multi-Stage Build
Compile in builder stage, copy to clean runtime stage.

**Pros:** Cleanest image
**Cons:** More complex Dockerfile
**Effort:** Medium
**Risk:** Low

## Recommended Action

<!-- Fill during triage -->

## Technical Details

**Affected files:**
- `airflow/Dockerfile`

**Components:** Docker image build

## Acceptance Criteria

- [ ] `build-essential` removed from final image
- [ ] Image size reduced by ~150-200MB
- [ ] All Python packages still work

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-03 | Created from code review | psycopg2-binary is precompiled wheel |

## Resources

- [Docker Best Practices](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
