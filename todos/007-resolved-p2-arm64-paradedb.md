---
status: pending
priority: p2
issue_id: "007"
tags: [code-review, architecture, docker, postgresql]
dependencies: []
---

# ARM64 Build Incompatibility with ParadeDB

## Problem Statement

The PostgreSQL Dockerfile hardcodes `amd64` architecture for the ParadeDB download, but CI/CD builds for both `linux/amd64` and `linux/arm64`. ARM64 builds will fail or install incompatible binaries.

**Why it matters:** Multi-architecture support is broken. ARM64 users (Apple Silicon, AWS Graviton) cannot use the PostgreSQL image.

## Findings

**File:** `postgres/Dockerfile`

| Line | Code | Issue |
|------|------|-------|
| 59-63 | `pg_search-v${PARADEDB_VERSION}-pg17-amd64-linux-gnu.deb` | Hardcoded `amd64` |

**File:** `.github/workflows/build-postgres.yml`

| Line | Code | Issue |
|------|------|-------|
| 58 | `platforms: linux/amd64,linux/arm64` | Builds both architectures |

## Proposed Solutions

### Option A: Conditional Architecture Download (Recommended)
Use Docker's `TARGETARCH` build arg.

**Pros:** Proper multi-arch support
**Cons:** Slightly more complex Dockerfile
**Effort:** Small
**Risk:** Low

```dockerfile
ARG TARGETARCH
ARG PARADEDB_VERSION=0.15.6
RUN if [ "$TARGETARCH" = "amd64" ]; then \
      curl -L "...amd64-linux-gnu.deb" -o /tmp/pg_search.deb; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
      curl -L "...arm64-linux-gnu.deb" -o /tmp/pg_search.deb; \
    fi && \
    dpkg -i /tmp/pg_search.deb && rm /tmp/pg_search.deb
```

### Option B: Build Only for amd64
Remove arm64 from CI/CD if not needed.

**Pros:** Simpler
**Cons:** Loses arm64 support
**Effort:** Small
**Risk:** Low

### Option C: Skip ParadeDB on ARM64
Make pg_search optional for arm64.

**Pros:** ARM64 builds work
**Cons:** Feature parity lost
**Effort:** Small
**Risk:** Medium

## Recommended Action

<!-- Fill during triage -->

## Technical Details

**Affected files:**
- `postgres/Dockerfile`
- `.github/workflows/build-postgres.yml`

**Components:** Docker build, CI/CD

## Acceptance Criteria

- [ ] ARM64 builds succeed
- [ ] ParadeDB installed on both architectures (or documented as amd64-only)
- [ ] CI/CD tests both architectures

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-03 | Created from code review | Docker provides TARGETARCH build arg |

## Resources

- [Docker Multi-Platform Builds](https://docs.docker.com/build/building/multi-platform/)
- [ParadeDB Releases](https://github.com/paradedb/paradedb/releases)
