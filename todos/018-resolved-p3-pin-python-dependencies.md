---
status: pending
priority: p3
issue_id: "018"
tags: [code-review, architecture, airflow, dependencies]
dependencies: []
---

# Unpinned Python Dependencies in Airflow Dockerfile

## Problem Statement

Python packages in the Airflow Dockerfile are not version-pinned, leading to non-reproducible builds.

**Why it matters:** A package update could break the build or introduce bugs without any code change.

## Findings

**File:** `airflow/Dockerfile`

| Line | Package | Issue |
|------|---------|-------|
| 33 | `requests` | Unpinned |
| 34 | `pandas` | Unpinned |
| 35 | `psycopg2-binary` | Unpinned |

## Proposed Solutions

### Option A: Create requirements.txt (Recommended)

```
# requirements.txt
apache-airflow-providers-postgres==5.12.0
apache-airflow-providers-redis==3.8.0
apache-airflow-providers-http==4.12.0
apache-airflow-providers-common-sql==1.15.0
requests==2.31.0
pandas==2.2.0
psycopg2-binary==2.9.9
```

```dockerfile
COPY requirements.txt /tmp/
RUN pip install --no-cache-dir -r /tmp/requirements.txt
```

**Pros:** Reproducible builds, better caching
**Cons:** Must update versions manually
**Effort:** Small
**Risk:** Low

### Option B: Pin Inline
Add versions directly in Dockerfile.

**Pros:** Simple
**Cons:** Less maintainable
**Effort:** Small
**Risk:** Low

## Recommended Action

<!-- Fill during triage -->

## Technical Details

**Affected files:**
- `airflow/Dockerfile`
- New: `airflow/requirements.txt`

**Components:** Airflow image build

## Acceptance Criteria

- [ ] All Python packages version-pinned
- [ ] requirements.txt created
- [ ] Dockerfile uses requirements.txt

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-03 | Created from code review | requirements.txt improves cacheability |

## Resources

- [pip requirements files](https://pip.pypa.io/en/stable/reference/requirements-file-format/)
