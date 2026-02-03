---
status: pending
priority: p1
issue_id: "003"
tags: [code-review, security, airflow, encryption]
dependencies: []
---

# Empty Fernet Key for Airflow Encryption

## Problem Statement

The Airflow Fernet key, used for encrypting sensitive data like connection passwords and variables, is set to an empty string.

**Why it matters:** Without a valid Fernet key, Airflow cannot properly encrypt sensitive data. Connection credentials stored in Airflow's metadata database will be unencrypted or fail to save.

## Findings

**File:** `airflow/docker-compose.yml`

| Line | Issue |
|------|-------|
| 15 | `AIRFLOW__CORE__FERNET_KEY: ''` |

An empty Fernet key means:
- Connection passwords may be stored in plaintext
- Variables marked as "sensitive" won't be encrypted
- Existing encrypted data cannot be decrypted after key rotation

## Proposed Solutions

### Option A: Generate Key at Build Time (Recommended for Dev)
Document key generation and require it in `.env`.

**Pros:** Simple, explicit
**Cons:** Key must be managed externally
**Effort:** Small
**Risk:** Low

```bash
# Generate Fernet key
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

# .env
AIRFLOW__CORE__FERNET_KEY=your_generated_key_here
```

### Option B: Auto-Generate on First Start
Create entrypoint script that generates key if not provided.

**Pros:** Automatic for dev
**Cons:** Key changes on container recreation
**Effort:** Medium
**Risk:** Medium (data loss on key change)

### Option C: Use Airflow's Built-in Key Generation
Airflow 2.x can auto-generate a key, but this should be explicit.

**Pros:** Zero config
**Cons:** Key not persisted, data loss on restart
**Effort:** None
**Risk:** High

## Recommended Action

<!-- Fill during triage -->

## Technical Details

**Affected files:**
- `airflow/docker-compose.yml`
- `airflow/airflow.cfg` (line 32 mentions env var override)

**Components:** Airflow encryption, connection storage

## Acceptance Criteria

- [ ] Fernet key sourced from environment variable
- [ ] `.env.example` includes placeholder for Fernet key
- [ ] README includes key generation command
- [ ] Warning if Fernet key is empty (optional)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-03 | Created from code review | Fernet keys must be 32 url-safe base64 bytes |

## Resources

- [Airflow Fernet Key Documentation](https://airflow.apache.org/docs/apache-airflow/stable/security/secrets/fernet.html)
