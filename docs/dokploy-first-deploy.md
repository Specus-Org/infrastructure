# Dokploy First Deploy

How to deploy the Specus infrastructure stack once you have a Dokploy admin account and can log in to the UI.

## Audience

This guide is written for an engineer who is comfortable with Docker, SSH, and DNS. It assumes Dokploy is already installed on a VPS and you have admin access to the Dokploy UI. If Dokploy is not yet installed, see the [official Dokploy install docs](https://docs.dokploy.com).

For day-two operations (redeploy, logs, rollback, troubleshooting), see [`dokploy-operations.md`](dokploy-operations.md).

## What you need before starting

1. Dokploy admin credentials and a reachable URL for the UI.
2. SSH access to the VPS running Dokploy (needed for discovering generated container hostnames and for running the Authentik DB bootstrap). The repo is expected to be cloned somewhere on that host, for example `/opt/specus`.
3. DNS you control for the domains you will use. This guide assumes Cloudflare.
4. The Dokploy GitHub App installed against `Specus-Org/infrastructure`. If that is not set up yet: in Dokploy, **Settings → Git → GitHub → Install GitHub App**, then grant access to the repo.
5. Let's Encrypt email set in Dokploy. In **Settings** there is a field for the email used for ACME registration. Dokploy does not issue any certs until this is set, and it does not warn you loudly that this is the reason.

## Step 1: Understand the service map

Before you deploy anything, internalize the dependency order. Services later in this list need services earlier in this list already running and healthy:

1. `specus-production-database` (Postgres)
2. `specus-production-redis`
3. `specus-production-garage` (object storage)
4. Airflow services (three separate Application deployments sharing one Dockerfile, each with a different command)
5. `specus-production-authentik` (needs Postgres and Redis and Garage)

Each of these is a separate Dokploy service. Do not deploy them all at once. Deploy and verify one, then move to the next.

## Step 2: Deploy Postgres first

In Dokploy, create a new project called `Infrastructure`, environment `production`. Inside it:

**+ Service → Application**
- Name: `specus-production-database`
- Build type: Dockerfile
- Git provider: GitHub
- Repository: `Specus-Org/infrastructure`
- Branch: `main`
- Build context path: `./postgres`
- Dockerfile: `Dockerfile` (default)

In the **Environment** tab, paste the contents of `postgres/.env.example` with real values filled in. Follow the generation commands in the comments. Never commit `.env` files to Git.

Click **Deploy**. Watch the Deployments tab until the build finishes and the container reports healthy. Note the generated container name from the **General** tab (something like `specus-production-database-a7k2m9`). This suffix is unique to your installation and will be important in the next step.

## Step 3: Discover your actual generated hostnames

The `.env.example` files in the repo default their host values to hostnames from the original Specus deployment (for example `POSTGRES_HOST=specus-production-database-rkpsij`). Your installation's suffixes will be different. Before deploying any service that depends on Postgres or Redis, you need to know your actual generated hostnames.

From the VPS shell:

```bash
docker network inspect dokploy-network \
  --format '{{range .Containers}}{{.Name}}{{println}}{{end}}' \
  | sort
```

Note down the hostname for each core service. You will paste these into the env vars of every consumer service.

## Step 4: Deploy Redis

Same shape as Postgres:

- Name: `specus-production-redis`
- Build context path: `./redis`
- Environment: `REDIS_PASSWORD=<openssl rand -base64 32>`

Click Deploy. Wait for healthy. No domain needed (Redis is internal-only, reached via the Docker network).

## Step 5: Initialize the Authentik database (required before deploying Authentik)

This is a hard gate. If you skip it, Authentik will crash-loop on startup with `FATAL: role "authentik_user" does not exist` and Dokploy's retry counter will burn through attempts. Run the SQL before clicking Deploy on Authentik.

Open `authentik/init-authentik.sql` on the VPS and edit `CHANGE_ME_SECURE_PASSWORD` to the value you plan to use for `AUTHENTIK_DB_PASSWORD`. The script has two SQL blocks. The first block (against the `postgres` database) creates the database and role. The second block (against the `authentik` database) only matters if your `authentik_user` did not end up as owner, which is rare on a clean install. Read the comments in the file before running.

Run the first block:

```bash
docker exec -i specus-production-database-<your-suffix> \
  psql -U postgres -d postgres < authentik/init-authentik.sql
```

Confirm the bootstrap worked:

```bash
docker exec specus-production-database-<your-suffix> \
  psql -U authentik_user -d authentik -c "SELECT 1"
```

If this returns `1`, you are ready to deploy Authentik.

## Step 6: Deploy Authentik

**+ Service → Compose** (not Application, this time, because Authentik has two containers):

- Name: `specus-production-authentik`
- Git provider: GitHub
- Repository: `Specus-Org/infrastructure`
- Branch: `main`
- Compose path: `./authentik/docker-compose.yml`

In the **Environment** tab, paste the contents of `authentik/.env.example` with real values. The important ones to set for your specific installation:

- `POSTGRES_HOST` must match your Postgres container name from Step 3 (override the default, which is from the original Specus deploy)
- `REDIS_HOST` must match your Redis container name from Step 3
- `AUTHENTIK_SECRET_KEY`, `AUTHENTIK_DB_PASSWORD`, `AUTHENTIK_BOOTSTRAP_PASSWORD` all get real generated values

Memory limits for compose services have to live in the compose file, not the Dokploy UI (the UI's `Advanced → Cluster Settings` only applies to Application services, not Compose services). The limits in `authentik/docker-compose.yml` are already sized for an 8 GB host.

## Step 7: Add the domain and DNS carefully

This is where the Let's Encrypt plus Cloudflare pitfall lives. Follow this sequence:

1. In Cloudflare DNS, add an A record:
   - Type: A, Name: `auth`, Target: your VPS IP
   - Proxy: **DNS only (grey cloud) for now**. Do not use the orange cloud yet.
2. Verify DNS propagation: `dig +short auth.specus.biz` should return your VPS IP within a minute or two.
3. In Dokploy, open the Authentik service, **Domains → + Add Domain**:
   - Domain: `auth.specus.biz`
   - Service: `authentik-server`
   - Container port: `9000`
   - HTTPS: enabled (Let's Encrypt)
4. Wait for Traefik to issue the cert. Watch the logs on the Traefik container if it takes more than a couple of minutes. A successful issuance looks like `Certificate obtained` in Traefik logs.
5. Only after the cert is issued, go back to Cloudflare and switch the A record to Proxied (orange cloud).

The reason for this dance: Dokploy's Traefik uses Let's Encrypt's HTTP-01 challenge by default, which needs unproxied port 80 traffic. With Cloudflare proxying enabled from the start, the challenge fails silently, Traefik retries, and after five failures per hostname per hour Let's Encrypt rate-limits you for up to a week. If you want Cloudflare proxying from the start, switch Traefik to the DNS-01 challenge with a Cloudflare API token (outside the scope of this guide).

## Step 8: First login and remove bootstrap credentials

Open `https://auth.specus.biz` and log in with `akadmin@specus.biz` and the value of `AUTHENTIK_BOOTSTRAP_PASSWORD` you set. Immediately do these:

1. Set up a secure password on the `akadmin` user and enable a second factor.
2. In Dokploy, open the Authentik service's **Environment** tab and delete `AUTHENTIK_BOOTSTRAP_PASSWORD` and `AUTHENTIK_BOOTSTRAP_TOKEN`. Redeploy. The bootstrap credentials are re-ingested on every deploy if they remain set, which defeats the point of rotating them.

The Authentik admin credential is the master for all services that delegate SSO to Authentik. Treat it accordingly. Use a password manager, not shell history or a note file.

## Where to back up your secrets

Dokploy stores environment variables encrypted at rest, but that encryption does not help you if the VPS or Dokploy database is lost. Keep your source of truth somewhere else (1Password, Bitwarden, Vault, an age-encrypted file in a separate repo, whatever your team uses). Rotating `AUTHENTIK_SECRET_KEY` without coordinating with the Fernet-encrypted data it protects is destructive, so this source of truth is load-bearing.

## What's next

- Add more services. Each one follows the same shape: provision the database first if needed, discover hostnames, set env vars, deploy, add domain through the grey-cloud-then-orange-cloud sequence.
- Operate the stack: see [`dokploy-operations.md`](dokploy-operations.md) for redeploy, rollback, logs, and troubleshooting.
- Reach VPN-only services (Postgres, Redis, Airflow UI, Garage admin UI) by connecting to wg-easy. Client setup is in `scripts/setup-wireguard-client.sh`.
