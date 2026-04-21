---
title: "feat: Add Apache Superset to Specus infrastructure"
type: feat
status: active
date: 2026-04-21
---

# feat: Add Apache Superset to Specus infrastructure

## Overview

Add Apache Superset as a new Dokploy-deployable service in the Specus infrastructure repo, following the existing pattern (custom image + compose-based stack + GHCR CI + README docs). Ship a production-shaped topology (web + Celery worker + Celery beat) that reuses the shared PostgreSQL and Redis core stack, authenticates against Superset's built-in DB auth for now, and connects to the shared `specus` Postgres as its first data source. Authentik SSO and additional warehouse drivers are deferred to follow-up iterations.

## Problem Frame

The platform needs a self-hosted BI/exploration tool so the team can build dashboards and run ad-hoc SQL against the shared Postgres without wiring custom UIs. Apache Superset is the chosen tool. It must:

- Deploy through Dokploy like every other service in this repo
- Share the existing PostgreSQL (`specus-production-database-rkpsij`) and Redis (`specus-production-redis-h08jhy`) core stacks rather than spinning up dedicated instances
- Live under `specus.biz` (e.g. `bi.specus.biz`) behind Traefik with HTTPS
- Build an image in CI and publish to GHCR alongside `specus-postgres`, `specus-redis`, `specus-airflow`
- Not disrupt the running Authentik/Airflow stacks or their Redis/Postgres usage

## Requirements Trace

- R1. Superset web UI is reachable at `bi.specus.biz` over HTTPS and lets a bootstrapped admin log in.
- R2. Superset metadata persists in a dedicated database on the shared Postgres instance (`superset` DB, `superset_user` role), isolated from other services.
- R3. Celery worker and beat run as separate containers using the shared Redis as broker + result backend + cache, on Redis DBs that do not collide with Authentik (DB 1).
- R4. SQL Lab async queries, alerts/reports, and scheduled dashboard caching are functional (validated by a smoke query through SQL Lab and a scheduled cache warm-up).
- R5. A custom image is built and pushed to `ghcr.io/<org>/specus-superset` on pushes to `main` touching `superset/**`, following the existing CI pattern.
- R6. Default connection to the shared `specus` database is documented so an operator can add it via the Superset UI on first boot; no custom DB drivers beyond the defaults shipped by `apache/superset` are required in this iteration.
- R7. All secrets (`SUPERSET_SECRET_KEY`, metadata DB password, Redis password, bootstrap admin credentials) are supplied via `.env` and never baked into the image.
- R8. README documents Superset alongside the other components: purpose, env vars, Dokploy wiring, resource allocation, bootstrap runbook.

## Scope Boundaries

- No Authentik SSO wiring in this plan — Superset uses its built-in `AUTH_DB` (username/password).
- No extra database drivers beyond what `apache/superset` ships by default (no BigQuery, Snowflake, Trino, ClickHouse, DuckDB in this iteration).
- No custom Superset visualization plugins, themes, or branding assets.
- No automated dashboard provisioning or git-sync of Superset assets (YAML imports/exports stay manual).
- No Prometheus scraping of Superset metrics beyond what comes out of the box.
- No changes to how Airflow or Authentik use the shared Postgres/Redis.

### Deferred to Separate Tasks

- Authentik OAuth2 integration (new `AUTH_TYPE=AUTH_OAUTH` config, client registration in Authentik admin UI, role mapping): follow-up plan after this one lands.
- Additional data-source drivers (warehouses or analytics engines): added per-source when a concrete need appears.
- Superset assets-as-code (version-controlled dashboards/datasets): deferred until usage patterns stabilize.

## Context & Research

### Relevant Code and Patterns

- `authentik/docker-compose.yml` — closest analogue for this plan. Two containers (`authentik-server`, `authentik-worker`) sharing Postgres + Redis from the core stack, dual-network (`authentik-internal` + `dokploy-network`), healthcheck, resource limits. Mirror this shape for Superset.
- `authentik/init-authentik.sql` — manual DB/user bootstrap pattern (`CREATE DATABASE`, `CREATE USER`, grants, default privileges). Mirror for Superset.
- `authentik/.env.example` — env file layout and generation-command commentary. Mirror for Superset.
- `airflow/Dockerfile` + `airflow/requirements.txt` — custom-image pattern (pin upstream image, layer in repo-specific requirements). Mirror for Superset if we need a custom image at all (see Unit 1 decision).
- `.github/workflows/build-airflow.yml` — CI template: path filter, buildx, GHCR login, `docker/metadata-action` tagging (branch/pr/tag/sha/latest), `docker/build-push-action@v6` with GHA cache. Copy structurally for Superset.
- `README.md` — service tables (Components, Resource Allocation, Dokploy environment variables), Directory Structure, Security Notes. Superset entries must be added here.
- Shared hosts already referenced by multiple stacks:
  - PostgreSQL: `specus-production-database-rkpsij:5432`
  - Redis: `specus-production-redis-h08jhy:6379`
  - Authentik already claims Redis DB `1`.

### Institutional Learnings

- Per auto-memory (`project_garage_authentik_deploy.md`): Authentik + Garage are live in the Dokploy Infrastructure/production environment; domain migration from `procurelens.org` → `specus.biz` is in flight. All Superset-facing names, domains, and env values use `specus.biz`.
- Existing stacks keep compose files self-contained and let operators run them through Dokploy's compose deployment. Superset should follow suit rather than introducing a deploy-time templating layer.

### External References

- Apache Superset "Installing with Docker Compose" docs: authoritative source for `superset_config.py` knobs, bootstrap command sequence (`superset db upgrade`, `superset fab create-admin`, `superset init`), and Celery config shape. Verify the pinned image tag against the latest stable Superset release at implementation time.

## Key Technical Decisions

- **Topology: web + Celery worker + Celery beat (3 containers).** Enables async SQL Lab, alerts/reports, and scheduled cache warm-up. Mirrors the Authentik server/worker split already running in this stack.
- **Reuse shared Postgres and Redis.** New `superset` database + `superset_user` role on the existing Postgres; no new Postgres instance. Metadata DB isolated from Authentik/Airflow DBs. Redis DB allocation: `2` for cache (results + filter/explore cache), `3` for Celery broker, `4` for Celery results backend — all free, Authentik still owns `1`. This is recorded in the README and env example so future services don't collide.
- **Authentication: local DB auth (`AUTH_TYPE=AUTH_DB`) for this iteration.** Bootstrap a single admin via `superset fab create-admin` on first deploy; additional users created in the UI. Authentik OAuth2 is a future iteration (follow-up plan), so design `superset_config.py` to keep the SSO swap to a localized change.
- **Custom Dockerfile, thin.** Start from `apache/superset:<pinned-tag>` and add only what's repo-specific: a bundled `superset_config.py` and a `requirements.txt` (kept empty or with minimal extras in this iteration). Keeping the Dockerfile in place now means adding drivers later is a requirements-file bump, not a new service shape.
- **Config file over env-only.** Ship `superset/superset_config.py` baked into the image (via `SUPERSET_CONFIG_PATH`), reading secrets from env vars. Superset has too many interrelated Python config knobs (Celery config dict, feature flags, cache config dict) to express cleanly through env alone.
- **Metadata DB bootstrap is manual.** Follow the Authentik pattern (`init-superset.sql` + DBeaver/psql). No automated migration; operators own first-time setup.
- **Separate internal network + dokploy-network.** `superset-internal` for container-to-container (web ↔ worker ↔ beat), `dokploy-network` for Traefik ingress to the web container only. Same shape as Authentik.
- **Resource targets:** web 1 GB / 0.5 CPU, worker 1 GB / 0.5 CPU, beat 256 MB / 0.25 CPU. Adds ~2.25 GB to the stack total (README currently reports ~6.7 GB). Call out in Risks.

## Open Questions

### Resolved During Planning

- **Which Redis DBs?** → Cache `2`, broker `3`, results `4`. Documented in README Redis-DB allocation table (new) to prevent future collisions.
- **Pin a Superset version?** → Yes, pin via `SUPERSET_VERSION` env with a default in `.env.example`. Exact tag is verified at implementation time against Superset's release notes (knowledge cutoff: Jan 2026).
- **Celery beat in its own container vs. in the worker?** → Separate container. Matches Superset's recommended production layout and avoids losing the scheduler if the worker restarts.
- **Do we need a custom image at all vs. upstream `apache/superset` + mounted config?** → Yes, a thin custom image. It lets CI pin the version, lets us bundle `superset_config.py` reproducibly, and leaves a clean seam for adding drivers later.

### Deferred to Implementation

- Exact pinned Superset image tag — verify latest stable at build time.
- Whether to keep `requirements.txt` empty initially or preinstall `pydruid`/connector extras we already expect — decide when the Dockerfile is written.
- Precise memory caps after observing real usage (the values in Key Decisions are starting points, not final).
- Concrete domain routing (Dokploy domain entry + Cloudflare DNS for `bi.specus.biz`) — configured in Dokploy as a deploy-time step, not in the repo.

## Output Structure

```
superset/
├── Dockerfile                 # FROM apache/superset:<pinned> + bundled config
├── requirements.txt           # Extra Python deps (empty or minimal this iteration)
├── superset_config.py         # Metadata DB, Celery, cache, secret key, auth
├── docker-compose.yml         # web + worker + beat, shared networks
├── init-superset.sql          # Manual DB + role bootstrap
├── .env.example               # All secrets/config with generation commands
└── bootstrap.md               # First-deploy runbook (fab create-admin, db upgrade, init)
.github/workflows/
└── build-superset.yml         # CI mirror of build-airflow.yml
```

## Implementation Units

- [ ] **Unit 1: Custom Superset Docker image**

**Goal:** Produce a reproducible `specus-superset` image pinned to a specific upstream Superset version, with the bundled `superset_config.py` baked in and an open seam for future Python dependencies.

**Requirements:** R5, R7

**Dependencies:** None

**Files:**
- Create: `superset/Dockerfile`
- Create: `superset/requirements.txt`

**Approach:**
- Base image: `apache/superset:<pinned-tag>` (tag decided at implementation time; surfaced via a build arg so CI can override).
- Install `requirements.txt` as the `superset` user (no `root` drift).
- Copy `superset_config.py` into `/app/pythonpath/` and set `SUPERSET_CONFIG_PATH` / `PYTHONPATH` so Superset picks it up automatically.
- Do not bake secrets, admin usernames, or site-specific values into the image. Everything tunable comes from env at container start.
- Do not set an `ENTRYPOINT`/`CMD` override — the upstream image already handles lifecycle; roles (web vs. worker vs. beat) are selected in compose via `command:`.

**Patterns to follow:**
- `airflow/Dockerfile` and `airflow/requirements.txt` — same thin-customization shape (pin upstream, layer repo requirements, don't fork entrypoint).

**Test scenarios:**
- Happy path: `docker build ./superset` completes and the resulting image starts with `apache/superset`-style help output when run without a command.
- Integration: container sees `superset_config.py` on `PYTHONPATH` (verified by `docker run ... python -c "import superset_config"` returning zero).

**Verification:**
- Local `docker build` succeeds.
- Running the image with no command reports Superset CLI usage.
- Image size and layer count are in line with other Specus images (i.e., the custom layer is thin, not a fresh base).

- [ ] **Unit 2: `superset_config.py` — metadata DB, Celery, cache, auth**

**Goal:** Encode all Superset Python-level configuration in a single repo-owned file that reads secrets from env, wires the metadata DB, the Celery app (broker + results + beat schedule shell), the cache, and the auth type.

**Requirements:** R2, R3, R4, R6, R7

**Dependencies:** None (but consumed by Unit 1 and Unit 4)

**Files:**
- Create: `superset/superset_config.py`

**Approach:**
- Source every secret (`SECRET_KEY`, DB password, Redis password) from `os.environ`. Fail fast (raise) if `SUPERSET_SECRET_KEY` is unset — never fall back to a default in production.
- `SQLALCHEMY_DATABASE_URI`: `postgresql+psycopg2://superset_user:<pw>@specus-production-database-rkpsij:5432/superset`, composed from env vars.
- Celery: define a `CeleryConfig` class with `broker_url` → Redis DB `3`, `result_backend` → Redis DB `4`, imports list for `superset.sql_lab` and `superset.tasks.scheduler`, and a `beat_schedule` stub for scheduled cache warm-up and reports.
- Cache: `CACHE_CONFIG`, `DATA_CACHE_CONFIG`, `FILTER_STATE_CACHE_CONFIG`, `EXPLORE_FORM_DATA_CACHE_CONFIG` all pointing at Redis DB `2` with distinct key prefixes.
- Feature flags: enable `ALERT_REPORTS`, `THUMBNAILS`, `DASHBOARD_RBAC` (tune at implementation time based on Superset's current stable defaults).
- Auth: `AUTH_TYPE = AUTH_DB`, `PUBLIC_ROLE_LIKE = "Gamma"` left unset (stay closed). Leave a `# Authentik SSO: see follow-up plan` anchor comment so the future swap is obvious.
- `TALISMAN_ENABLED = True` and `WEBDRIVER_BASEURL` set to the internal hostname so worker-rendered screenshots reach the web container over the internal network, not through Traefik.

**Patterns to follow:**
- Env-driven config pattern already in use across `authentik/docker-compose.yml` — everything sensitive arrives via env, never hard-coded.

**Test scenarios:**
- Happy path: importing `superset_config` in a container with required env vars set succeeds without raising.
- Error path: missing `SUPERSET_SECRET_KEY` raises a clear `RuntimeError` at import time (not at first request).
- Integration: the web container boots, can connect to the metadata DB, and the Celery worker picks up tasks enqueued by the web container on Redis DB 3.

**Verification:**
- `superset db upgrade` runs cleanly against the configured metadata DB on first deploy.
- Kicking off an async SQL Lab query from the web UI lands a task on Redis DB 3 and returns results via DB 4.
- Cache keys for a rendered chart appear on Redis DB 2 with the expected prefix.

- [ ] **Unit 3: Metadata database bootstrap (`init-superset.sql`)**

**Goal:** Provide a repeatable, reviewable SQL script to create the `superset` database and `superset_user` role on the shared Postgres, isolated from other services.

**Requirements:** R2, R7

**Dependencies:** None

**Files:**
- Create: `superset/init-superset.sql`

**Approach:**
- Two clearly commented steps, mirroring `authentik/init-authentik.sql`:
  1. While connected to `postgres`: `CREATE DATABASE superset;`, `CREATE USER superset_user WITH ENCRYPTED PASSWORD 'CHANGE_ME';`, `GRANT ALL PRIVILEGES ON DATABASE superset TO superset_user;`.
  2. While connected to `superset`: `GRANT ALL ON SCHEMA public TO superset_user;` plus `ALTER DEFAULT PRIVILEGES` for tables and sequences.
- Add a header comment telling the operator to replace `CHANGE_ME` with the password they set in `.env` and reminding them this script runs manually (DBeaver/psql), not on container start.
- Do **not** grant cross-database access — `superset_user` must not be able to read other service DBs.

**Patterns to follow:**
- `authentik/init-authentik.sql` — same structure, same commentary style.

**Test scenarios:**
- Happy path: after running both steps, `psql -U superset_user -d superset -c "SELECT 1"` succeeds over the shared Postgres service.
- Edge case: a second run of Step 1 fails with a clear `already exists` error (not silent); operator knows setup only needs to happen once.
- Security: `superset_user` cannot connect to `authentik` or `airflow` databases.

**Verification:**
- Operator can complete bootstrap using only this file plus the password from `.env`.
- No grants beyond what Superset needs appear in the script.

- [ ] **Unit 4: Compose stack (`docker-compose.yml`)**

**Goal:** Define the three Superset containers (web, worker, beat) on the dual-network pattern, with healthchecks, resource limits, and shared-core env wiring.

**Requirements:** R1, R3, R4, R5, R7

**Dependencies:** Unit 1 (image), Unit 2 (config), Unit 3 (metadata DB must exist before first start)

**Files:**
- Create: `superset/docker-compose.yml`

**Approach:**
- Three services, all using the same image built in Unit 1:
  - `superset-web`: `command: ["gunicorn", ...]` (the upstream default for the web role), `container_name: specus-superset-web`, `hostname: superset-web`, joined to both `superset-internal` and `dokploy-network`. Healthcheck hits `/health`.
  - `superset-worker`: `command: ["celery", "--app=superset.tasks.celery_app:app", "worker", ...]`, `container_name: specus-superset-worker`, internal network only. Healthcheck runs `celery inspect ping`.
  - `superset-beat`: `command: ["celery", "--app=superset.tasks.celery_app:app", "beat", ...]`, `container_name: specus-superset-beat`, internal network only. Healthcheck checks process liveness.
- Env block on every service points metadata DB + Redis at the shared core hosts by default (same style as `authentik/docker-compose.yml` lines 29-39, 85-95).
- Networks: declare `superset-internal` (bridge) and `dokploy-network` (external) at the bottom.
- Volumes: one named volume `superset-home` mounted at `/app/superset_home` on every service (for thumbnails, logs, local state). No bind mount to host.
- Resource `deploy.resources.limits` per Key Decisions.
- `restart: unless-stopped` on all three.
- Exact Celery command flags (concurrency, log level) are left for implementation — the surface is a `command:` list, not config we need to lock down in the plan.

**Patterns to follow:**
- `authentik/docker-compose.yml` — two-role split, dual-network, env style, resource limits.

**Test scenarios:**
- Happy path: `docker-compose --env-file .env up -d` brings all three containers to `healthy`, with web listening on `:8088` internally.
- Integration: web and worker both read/write the metadata DB and Redis DBs 2/3/4; web reaches worker through `superset-internal` (not Traefik).
- Error path: if the metadata DB is unreachable, web's healthcheck fails before Traefik routes traffic to it.
- Isolation: `specus-superset-worker` is not reachable from `dokploy-network` (verified by `docker network inspect`).

**Verification:**
- All three services report `healthy`.
- `specus-superset-web` is the only Superset container attached to `dokploy-network`.
- `/health` returns 200 through the internal network.

- [ ] **Unit 5: Environment example (`.env.example`)**

**Goal:** Document every Superset configuration knob with generation commands and safe defaults, mirroring the Authentik example's structure.

**Requirements:** R7, R8

**Dependencies:** Units 2, 3, 4 (this file documents their inputs)

**Files:**
- Create: `superset/.env.example`

**Approach:**
- Sections, in order: Core (secret key, pinned version, domain), Bootstrap admin (username, password, first/last name, email), Database (shared Postgres host/port + `SUPERSET_DB_*`), Redis (shared host/port + cache/broker/results DB numbers + password), Feature flags (optional overrides), Generation commands (footer).
- Every secret has an `# openssl rand ...` or `# python -c ...` comment above it, matching `authentik/.env.example`.
- Pre-fill non-secret defaults (`POSTGRES_HOST=specus-production-database-rkpsij`, `REDIS_HOST=specus-production-redis-h08jhy`, `SUPERSET_CACHE_REDIS_DB=2`, `SUPERSET_CELERY_BROKER_DB=3`, `SUPERSET_CELERY_RESULT_DB=4`, `SUPERSET_DOMAIN=bi.specus.biz`).
- A top-of-file banner: "DO NOT commit .env; usage: `docker-compose --env-file .env up -d`".

**Patterns to follow:**
- `authentik/.env.example` — section order, commentary style, generation commands.

**Test scenarios:**
- Test expectation: none — this is a documentation artifact. Verification is that every env var referenced in `docker-compose.yml` and `superset_config.py` also appears here with a safe default or a generation command.

**Verification:**
- `grep -oE '\$\{[A-Z_]+' superset/docker-compose.yml` yields no names missing from `.env.example`.
- No placeholder secrets contain real values.

- [ ] **Unit 6: First-deploy runbook (`bootstrap.md`)**

**Goal:** Give an operator a deterministic, copy-pasteable sequence to take a fresh Dokploy deploy from zero to a logged-in admin with the shared `specus` database registered as a connection.

**Requirements:** R1, R2, R6, R8

**Dependencies:** Units 3, 4, 5 (needs DB bootstrap + running stack + env file)

**Files:**
- Create: `superset/bootstrap.md`

**Approach:**
- Ordered sections:
  1. Prerequisites: core stack running, Postgres reachable, Redis reachable, `.env` filled in.
  2. Metadata DB bootstrap: run `init-superset.sql` (Step 1 against `postgres`, Step 2 against `superset`).
  3. First container start: `docker-compose --env-file .env up -d`.
  4. Schema migration: `docker exec specus-superset-web superset db upgrade`.
  5. Create admin: `docker exec -it specus-superset-web superset fab create-admin` (interactive) — read values from `.env` bootstrap section.
  6. Init roles/permissions: `docker exec specus-superset-web superset init`.
  7. Register the `specus` Postgres connection: navigate to Data → Databases → `+ Database`, paste the SQLAlchemy URI (pointed at a read-only role on the shared Postgres — operator owns creating that role in this step).
  8. Smoke test: run a SELECT through SQL Lab in async mode and verify it returns.
  9. Dokploy / Cloudflare: add `bi.specus.biz` → container `:8088` domain in Dokploy; add Cloudflare A record (proxied) per the Garage/Authentik precedent.
- Callouts for things that can only be done once (`fab create-admin`) vs. safe to re-run (`superset db upgrade`, `superset init`).

**Patterns to follow:**
- README §7 "Garage Setup" — same `SSH → exec → run commands` posture, same Dokploy/Cloudflare language.

**Test scenarios:**
- Test expectation: none — documentation artifact. Verified end-to-end in staging on first rollout.

**Verification:**
- Following the runbook top to bottom on a fresh Dokploy service yields a logged-in admin and a successful SQL Lab query in under ~20 minutes.

- [ ] **Unit 7: CI workflow (`build-superset.yml`)**

**Goal:** Build and push `specus-superset` to GHCR on pushes to `main` that touch `superset/**`, on PRs against `main` (build-only), on `superset-v*` tags, and via manual dispatch — matching the Airflow workflow exactly.

**Requirements:** R5

**Dependencies:** Unit 1 (image must be buildable)

**Files:**
- Create: `.github/workflows/build-superset.yml`

**Approach:**
- Copy `.github/workflows/build-airflow.yml` and rename references from `airflow` to `superset`.
- `paths:` filters: `superset/**`.
- `env.IMAGE_NAME`: `${{ github.repository }}/specus-superset`.
- Tag rules: branch / PR / `type=match,pattern=superset-v(.*),group=1` / manual tag input / `latest` on default branch / commit SHA.
- `context: ./superset`, `platforms: linux/amd64`, GHA cache, `provenance: false`.
- No secrets beyond `GITHUB_TOKEN` — identical to Airflow's workflow.

**Patterns to follow:**
- `.github/workflows/build-airflow.yml` — the template this unit clones structurally.

**Test scenarios:**
- Happy path: push to `main` changing `superset/Dockerfile` triggers a build and pushes `latest` and `<sha>` tags to GHCR.
- PR path: opening a PR that touches `superset/**` builds the image without pushing (validated by the run logs).
- Tag path: pushing `superset-v1.2.3` publishes `1.2.3` in addition to `latest`.
- Isolation: a push that only touches `airflow/**` does *not* trigger this workflow.

**Verification:**
- Workflow appears in the Actions tab with the correct name.
- A dry-run PR touching `superset/README.md` (or similar) produces a build log but no GHCR push.

- [ ] **Unit 8: README and component-table updates**

**Goal:** Make Superset a first-class citizen in the repo's top-level documentation so newcomers and future planning work can locate it the same way they find Authentik/Airflow.

**Requirements:** R8

**Dependencies:** Units 1-7 (everything they reference must exist)

**Files:**
- Modify: `README.md`

**Approach:**
- **Components table**: add `Apache Superset 4.x | apache/superset:<pinned> | Business intelligence & ad-hoc SQL`.
- **Dokploy Deployment → Create Services**: add three entries — `specus-superset-web`, `specus-superset-worker`, `specus-superset-beat` — all pointing at `ghcr.io/<username>/specus-superset:latest` with compose note "Deploy `superset/docker-compose.yml` as a Dokploy compose service (includes web + worker + beat)".
- **Environment Variables**: add a Superset block referring operators to `superset/.env.example`, same style as the Authentik block.
- **Service Dependencies**: update the ordered start list to insert Superset after Airflow.
- **Resource Allocation table**: add rows for the three Superset services and recompute the total (call out that the VPS must accommodate ~9 GB post-Superset).
- **Directory Structure**: add the `superset/` subtree.
- **Redis DB allocation (new small subsection under "Redis")**: document `0` = default/unused, `1` = Authentik, `2` = Superset cache, `3` = Superset Celery broker, `4` = Superset Celery results. This prevents future services from stomping.
- **Security Notes**: add a bullet noting Superset uses DB auth locally and is Authentik-SSO-ready as a follow-up; confirm no direct port exposure (Traefik only).
- **Registry URLs**: add `ghcr.io/<username>/specus-superset:latest`.

**Patterns to follow:**
- README treatment of Authentik and Airflow throughout the existing document.

**Test scenarios:**
- Test expectation: none — documentation-only. The diff must not alter any existing non-Superset rows or values.

**Verification:**
- A second reviewer reading only the README can locate Superset's purpose, env vars, resource footprint, and deployment steps without reading any other file.
- The new Redis DB allocation table matches what `superset/.env.example` and `authentik/.env.example` both declare.

## System-Wide Impact

- **Interaction graph:** Superset web talks to shared Postgres (new DB), shared Redis (new DBs 2/3/4), Celery worker, Celery beat. None of Authentik, Airflow, or Garage change behavior. Traefik gains one new route (`bi.specus.biz` → `specus-superset-web:8088`).
- **Error propagation:** A failed metadata-DB connection keeps the web container un-healthy, so Traefik does not route traffic to it — no user-visible 500s, just a deploy that does not come up. Worker/beat failures degrade async features (alerts, SQL Lab async, thumbnails) but do not break the web UI for sync queries.
- **State lifecycle risks:** Metadata DB bootstrap is manual and one-shot — running `init-superset.sql` twice fails loudly (desired). `superset db upgrade` is re-entrant. `fab create-admin` is not — running it twice with different values creates two admins (documented in the runbook).
- **API surface parity:** None — Superset introduces a new surface; it does not mirror an existing one.
- **Integration coverage:** The async SQL Lab path (web → Redis broker → worker → Redis results → web) and the beat-driven scheduled cache warm-up path cannot be proven by unit tests on any one service; they must be smoke-tested after the first deploy. Listed in Unit 4 test scenarios and Unit 6 runbook.
- **Unchanged invariants:** Authentik's Redis DB (`1`) and Airflow's Postgres DB (`airflow`) are untouched. No shared-core passwords rotate as part of this work. Dokploy's `dokploy-network` gains one new attached container (web only); internal service-to-service traffic stays on `superset-internal`.

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Shared Postgres capacity is already tight (1.5 GB cap, 50 max connections per README) and Superset adds a new service that opens a pool per web/worker container. | Size Superset SQLAlchemy pool conservatively in `superset_config.py` (e.g., `SQLALCHEMY_POOL_SIZE = 5, SQLALCHEMY_MAX_OVERFLOW = 5` across both metadata-DB and data-source pools). Monitor `pg_stat_activity` after rollout; raise Postgres `max_connections` in the core stack if contention appears — but only in a follow-up plan, not silently here. |
| Shared Redis is in `allkeys-lru` eviction mode with a 256 MB cap — Celery messages can be evicted under memory pressure, dropping queued tasks. | Accept for alerts/reports (re-run on next schedule). For SQL Lab async, document the limitation in the runbook and flag "bump Redis `maxmemory` or switch Celery to a dedicated broker" as a follow-up. Do not attempt to repartition Redis in this plan. |
| Adding ~2.25 GB of memory limits pushes the stack from ~6.7 GB to ~9 GB on the existing VPS, which may be close to the ceiling. | Call this out explicitly in the README update (Unit 8). If the VPS cannot absorb it, the operator can downscale worker memory or drop beat to another host — both are env/compose tweaks, not plan rewrites. |
| Superset bootstrap is a multi-step manual sequence — easy to skip a step on a later redeploy (e.g., `superset init`). | Bootstrap runbook (Unit 6) labels which commands are one-shot vs. idempotent. Redeploy operators can re-run idempotent ones safely. |
| Default DB auth means admin credentials live in `.env` and the Superset metadata DB — not rotated centrally. | Short-lived: Authentik SSO is the follow-up. Document in Security Notes (Unit 8). |

## Documentation / Operational Notes

- New `superset/bootstrap.md` is the single source for deploy-day steps; README only references it.
- Redis DB allocation table in README becomes the shared contract for future services — enforce that new services declare their DB there.
- Cloudflare + Dokploy domain steps for `bi.specus.biz` are captured in the runbook (Unit 6), not the repo, to stay consistent with how Garage and Authentik handle routing.
- Post-rollout, observe Postgres connection count and Redis memory for one week; record findings in `docs/solutions/` if either constraint bites, so the Authentik-SSO follow-up plan can account for it.

## Sources & References

- Related code: `authentik/docker-compose.yml`, `authentik/init-authentik.sql`, `authentik/.env.example`, `airflow/Dockerfile`, `airflow/requirements.txt`, `.github/workflows/build-airflow.yml`, `README.md`
- External docs: Apache Superset "Installing with Docker Compose", Superset Celery / Alerts & Reports guide (verify current URLs at implementation time)
- Context: auto-memory `project_garage_authentik_deploy.md` (shared-core host names, domain migration to `specus.biz`)
