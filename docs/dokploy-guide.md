# Dokploy Deployment Guide

A beginner-friendly walkthrough for deploying the Specus infrastructure stack on Dokploy. If you've never used Dokploy before - start here.

---

## What is Dokploy?

**Dokploy is an open-source, self-hosted platform that turns your own Linux server into a "Vercel/Heroku-style" deployment target.** You install it once on a VPS, then use its web UI to deploy applications from Git repos, Docker images, or Docker Compose files. It handles the messy parts for you:

- **Docker orchestration** - pulls images, starts containers, applies resource limits.
- **Traefik reverse proxy** - routes incoming HTTPS traffic to the right container based on domain.
- **Let's Encrypt SSL** - issues and renews TLS certificates automatically.
- **Service lifecycle** - restarts crashed containers, redeploys on Git push, rolls back bad deploys.
- **Environment management** - stores secrets per-service, injects them at runtime.
- **Monitoring** - live logs, resource graphs, healthcheck status.

Think of it as the thin UI layer that lets you run infrastructure on your own hardware without writing Kubernetes manifests or manual `docker run` commands.

### Why this repo uses Dokploy

Every service in this repo (`postgres/`, `redis/`, `airflow/`, `garage/`, `authentik/`, `superset/`) is packaged to deploy as an individual Dokploy service. You point Dokploy at this Git repo, tell it which compose file or Dockerfile to use, drop your secrets into the UI, and it handles the rest.

---

## What you need before starting

1. **A Linux VPS** (≥8 GB RAM for this full stack, Ubuntu 22.04+ or Debian 12+ recommended). Hetzner, DigitalOcean, Linode, and Vultr all work fine.
2. **Root or sudo SSH access** to that VPS.
3. **A domain name** (e.g. `specus.biz`) with DNS managed somewhere you control - this guide assumes **Cloudflare** since the existing setup uses it.
4. **A GitHub account** with access to the `Specus-Org/infrastructure` repo.
5. **Basic familiarity with the terminal** - `ssh`, editing files with `nano`/`vim`, reading `docker ps` output.

You do **not** need to know Docker deeply. Dokploy handles the `docker` commands for you; you just need to know what a container and an image are conceptually.

---

## Step 1: Install Dokploy on your VPS

SSH into your VPS and run the official installer:

```bash
curl -sSL https://dokploy.com/install.sh | sh
```

What this does:

- Installs Docker and Docker Compose if missing.
- Pulls the Dokploy container stack (Dokploy itself + Traefik).
- Starts everything on the host.
- Creates a `dokploy-network` Docker bridge network that all Dokploy-managed services join.
- Exposes the Dokploy UI on port **3000** of your VPS.

After it finishes, it prints a URL like `http://<your-vps-ip>:3000`. Open it in your browser and create the admin account.

> **First-time hardening:** The admin UI on port 3000 is public by default. As soon as you log in, go to **Settings → Server** and enable "Restrict UI access to authenticated users only" (already on by default in recent versions). For production, put it behind a VPN (like `wg-easy/` in this repo) or a Cloudflare Zero Trust tunnel.

---

## Step 2: Understand the mental model

Before clicking around, internalize these four concepts - everything in the UI maps to one of them:

### Project

A logical grouping of related services. In this repo we use **one project called `Infrastructure`** with sub-environments (`production`, `staging`). A project is just a folder in the UI - it has no runtime effect.

### Service

The actual deployable unit. Dokploy offers three flavors:

| Service type | When to use | Example |
|--------------|-------------|---------|
| **Application** | Build from a Dockerfile in a Git repo, or from a pre-built image on a registry | `specus-postgres` (custom Dockerfile with PG extensions) |
| **Database** | Spin up Postgres/MySQL/MongoDB/Redis from presets | *(not used here - we use custom Application builds instead)* |
| **Compose** | Deploy a multi-container stack from a `docker-compose.yml` | `specus-authentik` (server + worker), `specus-superset` (init + web + worker + beat) |

**Most services in this repo are Compose services** because they need multiple containers or complex wiring.

### Domain

A public hostname (e.g. `superset.specus.biz`) bound to a specific container port on a specific service. Dokploy configures Traefik to route incoming HTTPS traffic for that hostname to that container. Each service can have multiple domains (Garage has `storage.specus.biz` → port 3900 AND `cdn.specus.biz` → port 3902).

### Environment Variables

Per-service secrets and config. Dokploy stores them encrypted at rest and injects them into the container's environment at start. This is how `.env.example` files in this repo map to reality - you **do not commit `.env`**, you paste its contents into the Dokploy UI.

---

## Step 3: Connect your GitHub account

Before you can deploy, Dokploy needs to pull code from GitHub.

1. In Dokploy UI: **Settings → Git → GitHub**.
2. Click **Install GitHub App**. This walks you through creating a GitHub App that grants Dokploy read access to your repos.
3. Grant access to `Specus-Org/infrastructure`.
4. Back in Dokploy, the repo appears in the dropdown when you create services.

---

## Step 4: Your first deployment - walk through Redis

Let's deploy the simplest service (Redis) end-to-end so you see the full pattern. Once you've done this once, every other service is a variation on the same theme.

### 4a. Create the project

1. Click **+ Project** in the Dokploy sidebar.
2. Name it `Infrastructure`, pick `production` environment, save.

### 4b. Create the Redis service

1. Inside the project, click **+ Service → Application**.
2. Fill in:
   - **Name:** `specus-production-redis`
   - **Build type:** Dockerfile
   - **Git Provider:** GitHub
   - **Repository:** `Specus-Org/infrastructure`
   - **Branch:** `main`
   - **Build path:** `./redis` *(this is the Dockerfile's directory)*
3. Save.

### 4c. Set environment variables

Open the **Environment** tab of the new service. Copy the contents of `redis/.env.example`, fill in the real password, paste into the UI:

```
REDIS_PASSWORD=<generate with: openssl rand -base64 32>
```

Save.

### 4d. Configure resources

Open the **Advanced → Cluster Settings** tab. Set memory and CPU limits per the README's Resource Allocation table:

- Memory limit: `640MB`
- CPU limit: `0.25`

Save.

### 4e. Deploy

Click the big **Deploy** button in the top-right.

Dokploy will:
1. Clone the repo.
2. Run `docker build ./redis` to produce the `specus-redis` image.
3. Start a container from that image with your env vars applied.
4. Join the container to `dokploy-network`.

Watch the **Deployments** tab for live build logs. Success = a green checkmark and a container listed in **General → Status**.

### 4f. Verify

Open the **Logs** tab. You should see Redis boot messages and `Ready to accept connections`. No domain needed - Redis is internal-only, other services reach it via `specus-production-redis-<suffix>:6379` on the shared Docker network.

**Congratulations - you've deployed your first service.** Everything else follows the same pattern with minor variations.

---

## Step 5: Deploy a compose service (Authentik example)

Multi-container services use a `docker-compose.yml` instead of a single Dockerfile. The deploy flow is similar but with one extra step.

### 5a. Create the Authentik service

1. **+ Service → Compose** inside the same project.
2. Fill in:
   - **Name:** `specus-production-authentik`
   - **Git Provider:** GitHub
   - **Repository:** `Specus-Org/infrastructure`
   - **Branch:** `main`
   - **Compose path:** `./authentik/docker-compose.yml`

### 5b. Environment variables

Copy `authentik/.env.example`, fill in values, paste into Dokploy **Environment** tab. Notice how `docker-compose.yml` uses `${VAR_NAME}` placeholders - Dokploy passes your env vars through to compose the same way `--env-file .env` would locally.

> **Pre-deploy requirement:** Authentik needs its metadata DB initialized first. Follow `authentik/init-authentik.sql` via a SQL client (DBeaver, pgAdmin, or `psql` from another container) before deploying. The same applies to `superset/init-superset.sql`. These manual SQL steps are listed in each service's `bootstrap.md` or in the README.

### 5c. Add a domain

1. Open **Domains** tab.
2. **+ Add Domain**:
   - **Domain:** `auth.specus.biz`
   - **Service/container:** `authentik-server`
   - **Container port:** `9000`
   - **HTTPS:** enabled (Let's Encrypt will auto-issue the cert)
3. Save.

### 5d. Cloudflare DNS

Before the domain resolves publicly, add an `A` record in Cloudflare:

| Type | Name | Target | Proxy |
|------|------|--------|-------|
| A | auth | `<your-vps-ip>` | Proxied (orange cloud) |

Cloudflare handles global SSL termination + DDoS; Dokploy/Traefik handles ingress routing on the VPS.

### 5e. Deploy

Click **Deploy**. Compose services take longer (multiple containers boot in sequence). Watch the **Deployments** tab.

Once green, visit `https://auth.specus.biz` - you should see Authentik's login page.

---

## Step 6: The Specus-specific conventions

These patterns are used across every service in this repo - recognize them and deployment becomes mechanical.

### Shared core services

Some services are **shared infrastructure** that other services depend on. Start them in this order:

1. `specus-production-database` (Postgres)
2. `specus-production-redis` (Redis)
3. `specus-production-garage` (S3 + CDN)

Then deploy consumers:

4. `specus-production-airflow-*` (uses Postgres)
5. `specus-production-authentik` (uses Postgres + Redis + Garage)
6. `specus-production-superset` (uses Postgres + Redis)

### Hostname convention

Dokploy auto-generates container hostnames like `specus-production-database-rkpsij`. Other services reference each other via these hostnames over `dokploy-network`. Env files in this repo default to the real production hostnames:

```
POSTGRES_HOST=specus-production-database-rkpsij
REDIS_HOST=specus-production-redis-h08jhy
```

If your deployment generates different suffixes, update these env vars per-service.

### Shared network

All Dokploy-managed services join `dokploy-network` automatically. Compose files in this repo declare it as `external: true`:

```yaml
networks:
  dokploy-network:
    external: true
```

This is how `superset-web` reaches `specus-production-database-rkpsij` without any port exposure.

### One compose = one Dokploy service

A compose file with multiple services (Superset has 4) becomes **one** Dokploy service. Dokploy manages the whole compose stack as a unit - deploy/restart/rollback all apply to the whole stack.

### `.env.example` is the contract

Every service directory has `.env.example` listing every required variable with generation commands. The golden rule: if a key appears in `docker-compose.yml` as `${FOO}`, it's in `.env.example`. When deploying, `.env.example` is your copy-paste template for the Dokploy Environment tab.

---

## Common operations

### Redeploy after a code change

1. Push your commit to `main`.
2. In Dokploy, click **Deploy** on the affected service. Dokploy will `git pull`, rebuild if needed, and restart.
3. (Optional) Enable **Auto-deploy** on the service so a push to `main` triggers redeploy automatically via webhook.

### View live logs

**Logs** tab → pick a container (for compose, pick which service). Updates in real time. Filter by keyword at the top.

### Exec into a container

**Terminal** tab → choose the container. You get a shell inside the running container. Useful for:

```bash
# Run Superset admin creation
superset fab create-admin ...

# Check Postgres from inside
psql -U postgres -d specus

# Redis CLI
redis-cli -a $REDIS_PASSWORD
```

### Update an environment variable

**Environment** tab → edit → save → click **Deploy** (changes don't apply until the container restarts).

### Rollback a bad deploy

**Deployments** tab → find the last working deployment → **Rollback**. Dokploy redeploys the previous image/commit.

### Scale resources

**Advanced → Cluster Settings** → change memory/CPU limits → redeploy. Limits only apply after restart.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `ErrImagePull` during deploy | Custom image not built/pushed yet, or wrong image path | Check the **Deployments** build logs. If the service uses a Dockerfile, verify Dokploy cloned the repo correctly. |
| Domain shows `404 Not Found` | Traefik doesn't have a route; domain or container port mismatch | Double-check **Domains** tab: the container name + port must match a running container. |
| Domain shows `Bad Gateway` / `502` | Container is up but not listening on the port Dokploy thinks | `docker exec` into the container and `curl localhost:<port>/health` - if that fails, the app didn't bind or is still starting. |
| SSL cert error | Let's Encrypt rate limit, or DNS hasn't propagated yet | Wait 5-10 minutes after adding the DNS record before enabling HTTPS in Dokploy. Check Traefik logs. |
| Service can't reach Postgres/Redis | Wrong hostname in env vars, or services not on the same Docker network | Verify the hostname matches what `docker ps` shows. All services should be on `dokploy-network`. |
| Container OOM-killed (`Exit 137`) | Memory limit too low for actual usage | Bump the limit in **Advanced → Cluster Settings** and redeploy. Check `docker stats` for real usage. |
| Disk full | Docker accumulating dead images/volumes | SSH into host: `docker system prune -a --volumes` (reclaims unused). Schedule this monthly. |
| Can't SSH into Dokploy UI | Installer exposes port 3000; firewall may be blocking | Check `ufw status` and allow port 3000 from your IP, or tunnel via `ssh -L 3000:localhost:3000`. |
| "Compose file not found" | Wrong **Compose path** in service config | Must be relative to repo root, include the filename, e.g. `./authentik/docker-compose.yml`. |

### Where to look when stuck

1. **Deployments tab** → build logs (shows `docker build` and `docker-compose pull`/`up` output)
2. **Logs tab** → runtime logs from each container
3. **Terminal tab** → `docker logs <container>` or `docker exec -it <container> sh`
4. On the VPS: `docker ps -a` (see all containers including exited), `docker network inspect dokploy-network`

---

## Service deploy reference (this repo)

Quick cheatsheet for each service. Always reference the service's own `.env.example` for the full variable list.

| Service | Type | Path | Depends on | Domain(s) |
|---------|------|------|-----------|-----------|
| `specus-production-postgres` | Application (Dockerfile) | `./postgres` | - | - (internal only) |
| `specus-production-redis` | Application (Dockerfile) | `./redis` | - | - (internal only) |
| `specus-production-airflow-*` | Application (Dockerfile) × 3 services, each with different command override | `./airflow` | Postgres | `airflow.specus.biz` → port 8080 |
| `specus-production-garage` | Compose | `./garage/docker-compose.yml` | - | `storage.specus.biz` → 3900, `cdn.specus.biz` → 3902 |
| `specus-production-authentik` | Compose | `./authentik/docker-compose.yml` | Postgres, Redis, Garage | `auth.specus.biz` → port 9000 (container: `authentik-server`) |
| `specus-production-superset` | Compose | `./superset/docker-compose.yml` | Postgres, Redis | `superset.specus.biz` → port 8088 (container: `superset-web`) |

Each service has its own deploy instructions in:
- `README.md` § Dokploy Deployment (high-level overview of all services)
- `<service>/.env.example` (secret values)
- `<service>/bootstrap.md` (where it exists - e.g. Superset, Garage post-install SQL/CLI steps)

---

## Next steps

Once you've deployed your first service:

1. **Read the service's `bootstrap.md`** (if present) - many services need one-time setup after first deploy (admin user creation, bucket init, database migration).
2. **Update your auto-memory or team runbook** with the actual generated hostnames (`specus-production-<service>-<suffix>`) so future deploys can reference them in env vars.
3. **Set up monitoring** - Dokploy's Monitoring tab gives basic metrics; for serious production, add Prometheus/Grafana or send logs to a central service.
4. **Configure backups** - Dokploy doesn't back up your volumes by default. For Postgres, schedule `pg_dump` via a cron container. For Garage, replicate to an external S3 bucket.
5. **Harden the host** - enable `ufw`, restrict port 3000 (Dokploy UI), enable fail2ban, turn off root SSH.

## Reference

- **Dokploy docs:** https://docs.dokploy.com
- **Dokploy GitHub:** https://github.com/Dokploy/dokploy
- **This repo's README:** `../README.md` - canonical source for service list, env vars, resource allocation
- **Service runbooks:** `superset/bootstrap.md`, and the "Garage Setup" section in the main README
