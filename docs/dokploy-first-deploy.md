# Dokploy First Deploy

How to bring up the Specus infrastructure stack on a fresh VPS using Dokploy.

## Audience

This guide is written for an engineer who is comfortable with Docker, SSH, and DNS, but has not used Dokploy before. If you have never used Docker or provisioned a VPS, the [official Dokploy getting-started docs](https://docs.dokploy.com) cover that ground better.

For day-two operations (redeploy, logs, rollback, troubleshooting), see [`dokploy-operations.md`](dokploy-operations.md).

## When to use Dokploy

Dokploy is a self-hosted UI layer on top of Docker and Traefik. It handles image builds from Git, per-service environment variables, TLS via Let's Encrypt, and live logs. It is a good fit when you want:

- A single-VPS or small-cluster deployment, not a full Kubernetes setup
- UI-driven deploys instead of writing your own CI pipelines
- Automatic TLS and reverse-proxy routing from a domain to a container

It is not a fit if you need multi-region, managed databases, or strict GitOps (where the repo is the source of truth for what is deployed). With Dokploy, environment variables and domain routing live in the UI, not in Git.

## What you need before starting

1. A Linux VPS, Ubuntu 22.04 or 24.04, at least 8 GB RAM and 40 GB disk. Hetzner, DigitalOcean, Vultr, and Linode all work.
2. SSH key authentication configured before you touch the VPS. Password auth over SSH is out of scope, we assume key-only.
3. A cloud firewall you can configure before installing anything. Vultr, DigitalOcean, and Hetzner all expose this in their control panel. We use this to restrict port 3000 to your IP during Dokploy setup. An example ruleset lives at `firewall/vultr/specus-vps.md`.
4. A domain with DNS you control. This guide assumes Cloudflare, matching the existing setup.
5. A GitHub account with read access to `Specus-Org/infrastructure`.

## Step 1: Lock down the VPS before Dokploy goes on it

Apply these restrictions in your cloud provider's firewall, from your provider's UI, before running any install commands:

- Allow SSH (TCP 22) only from your own IP
- Allow Dokploy UI (TCP 3000) only from your own IP
- Allow HTTP (TCP 80) and HTTPS (TCP 443) from anywhere (Let's Encrypt needs port 80 to reach Traefik during cert issuance)
- Block everything else inbound

The reason this happens first is that Dokploy's UI opens on port 3000 as soon as the installer finishes. If the firewall is not in place, anyone on the internet can reach the admin signup page during the setup window.

SSH to the VPS and run:

```bash
sudo apt update && sudo apt upgrade -y
```

Then reboot if a new kernel was installed.

## Step 2: Install Dokploy

As root on the VPS:

```bash
curl -sSL https://dokploy.com/install.sh | sh
```

The installer does three things: it installs Docker if missing, initializes Docker Swarm mode, and starts Dokploy and Traefik on the host. It binds ports 80, 443, and 3000.

If the installer complains about an existing Docker installation or an existing Swarm node, stop and clean up before continuing. The installer is not designed to merge into an existing Docker setup.

When it finishes, open `http://<your-vps-ip>:3000` in your browser and create the admin account. Dokploy admin access is equivalent to root on the host (anyone with Docker access can read every container's environment variables, mount host paths, or escape to the host). Treat this account like a root password.

## Step 3: Run the repo hardening scripts

Clone the repo on the VPS and run the hardening scripts that handle the rest of the host setup (swap, timezone, `unattended-upgrades`, fail2ban, SSH hardening):

```bash
cd /opt
sudo git clone https://github.com/Specus-Org/infrastructure.git specus
cd specus/scripts
sudo ./setup-vps.sh
sudo ./harden-ssh.sh
```

`setup-vps.sh` also deploys `wg-easy` so you can reach the VPN-only services (Postgres, Redis, Airflow UI) later without exposing them through Traefik. Once the VPN is up, tighten your cloud firewall to only allow port 3000 from inside the VPN.

## Step 4: Configure Let's Encrypt in Dokploy

In the Dokploy UI, open **Settings** and set the Let's Encrypt email address. Dokploy will not issue any certs until this is set, and it does not warn you loudly that this is the reason. Do this before you deploy any service with a public domain.

## Step 5: Connect GitHub

**Settings → Git → GitHub → Install GitHub App**. Grant access to `Specus-Org/infrastructure`. Dokploy uses this to pull code during deploys.

## Step 6: Understand the service map

Before you deploy anything, internalize the dependency order. Services later in this list need services earlier in this list already running and healthy:

1. `specus-production-database` (Postgres)
2. `specus-production-redis`
3. `specus-production-garage` (object storage)
4. Airflow services (three separate Application deployments sharing one Dockerfile, each with a different command)
5. `specus-production-authentik` (needs Postgres and Redis and Garage)

Each of these is a separate Dokploy service. Do not deploy them all at once. Deploy and verify one, then move to the next.

## Step 7: Deploy Postgres first

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

## Step 8: Discover your actual generated hostnames

The `.env.example` files in the repo default their host values to hostnames from the original Specus deployment (for example `POSTGRES_HOST=specus-production-database-rkpsij`). Your installation's suffixes will be different. Before deploying any service that depends on Postgres or Redis, you need to know your actual generated hostnames.

From the VPS shell:

```bash
docker network inspect dokploy-network \
  --format '{{range .Containers}}{{.Name}}{{println}}{{end}}' \
  | sort
```

Note down the hostname for each core service. You will paste these into the env vars of every consumer service.

## Step 9: Deploy Redis

Same shape as Postgres:

- Name: `specus-production-redis`
- Build context path: `./redis`
- Environment: `REDIS_PASSWORD=<openssl rand -base64 32>`

Click Deploy. Wait for healthy. No domain needed (Redis is internal-only, reached via the Docker network).

## Step 10: Initialize the Authentik database (required before deploying Authentik)

This is a hard gate. If you skip it, Authentik will crash-loop on startup with `FATAL: role "authentik_user" does not exist` and Dokploy's retry counter will burn through attempts. Run the SQL before clicking Deploy on Authentik.

From the VPS shell:

```bash
cd /opt/specus
# First block of init-authentik.sql runs against 'postgres' database
docker exec -i specus-production-database-<your-suffix> \
  psql -U postgres -d postgres < authentik/init-authentik.sql
```

Open `authentik/init-authentik.sql` first and edit `CHANGE_ME_SECURE_PASSWORD` to the value you plan to use for `AUTHENTIK_DB_PASSWORD`. The script has two SQL blocks (one for the `postgres` database, one for the `authentik` database). The second block only matters if your `authentik_user` did not end up as owner, which is rare on a clean install. Read the comments in the file before running.

Confirm the bootstrap worked:

```bash
docker exec specus-production-database-<your-suffix> \
  psql -U authentik_user -d authentik -c "SELECT 1"
```

If this returns `1`, you are ready to deploy Authentik.

## Step 11: Deploy Authentik

**+ Service → Compose** (not Application, this time, because Authentik has two containers):

- Name: `specus-production-authentik`
- Git provider: GitHub
- Repository: `Specus-Org/infrastructure`
- Branch: `main`
- Compose path: `./authentik/docker-compose.yml`

In the **Environment** tab, paste the contents of `authentik/.env.example` with real values. The important ones to set for your specific installation:

- `POSTGRES_HOST` must match your Postgres container name from Step 8 (override the default, which is from the original Specus deploy)
- `REDIS_HOST` must match your Redis container name from Step 8
- `AUTHENTIK_SECRET_KEY`, `AUTHENTIK_DB_PASSWORD`, `AUTHENTIK_BOOTSTRAP_PASSWORD` all get real generated values

Memory limits for compose services have to live in the compose file, not the Dokploy UI (the UI's `Advanced → Cluster Settings` only applies to Application services, not Compose services). The limits in `authentik/docker-compose.yml` are already sized for an 8 GB host.

## Step 12: Add the domain and DNS carefully

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

## Step 13: First login and remove bootstrap credentials

Open `https://auth.specus.biz` and log in with `akadmin@specus.biz` and the value of `AUTHENTIK_BOOTSTRAP_PASSWORD` you set. Immediately do these:

1. Set up a secure password on the `akadmin` user and enable a second factor.
2. In Dokploy, open the Authentik service's **Environment** tab and delete `AUTHENTIK_BOOTSTRAP_PASSWORD` and `AUTHENTIK_BOOTSTRAP_TOKEN`. Redeploy. The bootstrap credentials are re-ingested on every deploy if they remain set, which defeats the point of rotating them.

The Authentik admin credential is the master for all services that delegate SSO to Authentik. Treat it accordingly. Use a password manager, not shell history or a note file.

## Where to back up your secrets

Dokploy stores environment variables encrypted at rest, but that encryption does not help you if the VPS or Dokploy database is lost. Keep your source of truth somewhere else (1Password, Bitwarden, Vault, an age-encrypted file in a separate repo, whatever your team uses). Rotating `AUTHENTIK_SECRET_KEY` or Authentik's Fernet key without coordinating with stored database credentials is destructive, so this source of truth is load-bearing.

## What's next

- Add more services. Each one follows the same shape: provision the database first if needed, discover hostnames, set env vars, deploy, add domain through the grey-cloud-then-orange-cloud sequence.
- Operate the stack: see [`dokploy-operations.md`](dokploy-operations.md) for redeploy, rollback, logs, and troubleshooting.
- Reach VPN-only services (Postgres, Redis, Airflow UI, Garage admin UI) by connecting to wg-easy. Client setup is in `scripts/setup-wireguard-client.sh`.
