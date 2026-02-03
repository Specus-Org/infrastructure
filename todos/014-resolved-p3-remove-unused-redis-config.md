---
status: pending
priority: p3
issue_id: "014"
tags: [code-review, simplification, redis, yagni]
dependencies: []
---

# Unused Redis Configuration Options

## Problem Statement

The Redis configuration includes settings for features not being used (replicas, pub/sub buffer limits, latency monitoring, Lua scripting).

**Why it matters:** Extra configuration adds cognitive load and maintenance burden without providing value.

## Findings

**File:** `redis/redis.conf`

| Lines | Setting | Issue |
|-------|---------|-------|
| 69-72 | `client-output-buffer-limit replica/pubsub` | No replicas, pubsub disabled |
| 98-101 | Latency monitor | Not needed for simple cache |
| 104-107 | Keyspace events | Disabled anyway |
| 110-112 | Lua scripting timeout | Default is fine |

**Reduction:** ~20 lines

## Proposed Solutions

### Option A: Remove Unused Settings (Recommended)
Keep only what's actively used.

**Pros:** Cleaner, focused config
**Cons:** Must add back if needed
**Effort:** Small
**Risk:** Low

### Option B: Keep with Comments
Document why settings exist.

**Pros:** Ready for future
**Cons:** More to maintain
**Effort:** None
**Risk:** None

## Recommended Action

<!-- Fill during triage -->

## Technical Details

**Affected files:**
- `redis/redis.conf`

**Components:** Redis configuration

## Acceptance Criteria

- [ ] Unused settings removed
- [ ] Redis still functions correctly
- [ ] Config file is more focused

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-03 | Created from code review | Redis defaults are sensible |

## Resources

- [Redis Configuration](https://redis.io/docs/manual/config/)
