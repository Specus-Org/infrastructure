---
status: pending
priority: p2
issue_id: "010"
tags: [code-review, architecture, ci-cd, testing]
dependencies: []
---

# No Integration Testing in CI/CD Pipelines

## Problem Statement

The GitHub Actions workflows only build images but don't verify that containers actually start, pass healthchecks, or have the expected extensions installed.

**Why it matters:** Broken images could be pushed to the registry and deployed to production without detection.

## Findings

**Files:** `.github/workflows/build-*.yml`

Current workflow steps:
1. Checkout
2. Setup Docker Buildx
3. Login to registry
4. Build and push

**Missing steps:**
- Start container and verify healthcheck
- Test PostgreSQL extensions exist
- Verify Redis responds to PING
- Check Airflow webserver returns 200

## Proposed Solutions

### Option A: Add Test Step After Build (Recommended)

```yaml
- name: Test container health
  if: github.event_name == 'pull_request'
  run: |
    docker run -d --name test-postgres \
      -e POSTGRES_PASSWORD=test \
      ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
    sleep 30
    docker exec test-postgres pg_isready -U postgres
    docker exec test-postgres psql -U postgres -c "SELECT extname FROM pg_extension"
    docker stop test-postgres
```

**Pros:** Catches broken images before merge
**Cons:** Adds ~1 min to build time
**Effort:** Small
**Risk:** Low

### Option B: Separate Test Workflow
Run integration tests as a separate workflow.

**Pros:** Parallel execution
**Cons:** More workflow files
**Effort:** Medium
**Risk:** Low

## Recommended Action

<!-- Fill during triage -->

## Technical Details

**Affected files:**
- `.github/workflows/build-postgres.yml`
- `.github/workflows/build-redis.yml`
- `.github/workflows/build-airflow.yml`

**Components:** CI/CD pipelines

## Acceptance Criteria

- [ ] Each workflow verifies container starts successfully
- [ ] Healthchecks pass before merge
- [ ] PostgreSQL extensions verified
- [ ] Test failures block merge

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-03 | Created from code review | Can use docker run in GHA |

## Resources

- [GitHub Actions Docker](https://docs.github.com/en/actions/creating-actions/dockerfile-support-for-github-actions)
