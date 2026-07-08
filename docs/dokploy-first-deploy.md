# Deploying Your Service on Specus

How to deploy a new application onto the Specus infrastructure using Dokploy.

## Audience

You are a developer who has an application to deploy, and the Specus infrastructure team has given you a Dokploy account on their instance. The shared platform services (PostgreSQL, Redis, Garage object storage, Authentik SSO, Airflow) are already running. This guide shows how to wire your application to those services, add a public domain, and operate the result.

For day-two operations (redeploy, rollback, logs, troubleshooting), see [`dokploy-operations.md`](dokploy-operations.md).

## What's already running

The infrastructure team manages these shared services. You do not deploy them, you connect to them.

| Shared service | What it is | How you use it |
|---|---|---|
| PostgreSQL 17 | Primary relational database with extensions (pg_cron, pg_search, Apache AGE) | Ask the infra team for a dedicated database + role for your service. Never reuse another service's credentials |
| Redis 7 | Cache and Celery broker, 512 MB, LRU eviction | Ask for a dedicated Redis DB number (0 is unused, 1 is Authentik, higher numbers are available) |
| Garage | S3-compatible object storage (`storage.specus.biz`) + read-only CDN (`cdn.specus.biz`) | Ask for an S3 access key and a bucket. Your app talks S3 to `https://storage.specus.biz` |
| Authentik | Identity provider + SSO at `auth.specus.biz` | Ask the infra team to register an OAuth2 client for your service. You get a client ID and secret to wire into your app's auth layer |
| Airflow | Scheduled workflows | If you need scheduled jobs, coordinate with whoever owns the Airflow DAGs repo |

Everything runs on a shared Docker network called `dokploy-network`. Your service joins this network automatically when you deploy through Dokploy, so you reach the shared services by container hostname, not by public URL.

## Before you start

1. You have a Dokploy account and can log in.
2. The infra team has granted you access to the project (or created one for your service) inside Dokploy.
3. You know the container hostnames for any shared services you need to reach. Ask the infra team for the current ones, or pull them yourself from the Dokploy UI (click on the Postgres or Redis service, the hostname is on the General tab). They look like `specus-production-database-rkpsij`.
4. Your app's code is in a GitHub repo that Dokploy can reach. If the GitHub App is not yet installed on your repo, ask the infra team to grant access.
5. You know which shared services your app needs and have requested credentials.

## Step 1: Choose a service shape

Dokploy has three service types worth knowing about. Pick based on your app:

- **Application (Dockerfile)**: you have a single container and a `Dockerfile` in your repo. This is the common case for web apps, APIs, and workers.
- **Application (Docker image)**: you have a prebuilt image on a registry (GHCR, Docker Hub). Point Dokploy at the image and it will pull and run it.
- **Compose**: your app has more than one container (web + worker, or app + nginx, or anything multi-container) and you want to describe them together in a `docker-compose.yml`.

If your app has a single container today but might split later, start with a Dockerfile Application. Switching to Compose later is a few minutes of work.

## Step 2: Create the service in Dokploy

In Dokploy, inside the project your team uses:

**+ Service → Application** (or **Compose** if you need more than one container)

Fill in:
- **Name**: something stable like `my-app-production`. This becomes the container name on the host and is surfaced in logs.
- **Git provider**: GitHub
- **Repository**: your repo
- **Branch**: `main` (or whichever branch you deploy from)
- **Build context path**: the directory with your `Dockerfile` or `docker-compose.yml`. `./` if they are at the repo root.

Do not click Deploy yet. The Environment tab is empty, and the service will crash-loop without its config.

## Step 3: Request credentials for shared services

For each shared service your app uses, ask the infra team to create credentials for you. Be specific so they can reply without a back-and-forth:

- **Postgres**: "Please create a database `myapp` and a role `myapp_user` with full privileges on that database only." They will give you the password and confirm the host + database + role.
- **Redis**: "Please assign me a Redis DB number." They will tell you which one (likely 2 or higher, since 0 is unused and 1 is Authentik).
- **Garage / S3**: "Please create a bucket `myapp-uploads` and an access key with read and write on it." They will give you the access key ID and secret.
- **Authentik OAuth2**: "Please register an OAuth2 client for `myapp` with redirect URL `https://myapp.specus.biz/auth/callback`." They will give you the client ID, client secret, and the discovery URL `https://auth.specus.biz/application/o/myapp/.well-known/openid-configuration`.

Write all of these down in your password manager before moving on. They are hard to regenerate without a coordinated rotation.

## Step 4: Fill in the Environment tab

In your service's **Environment** tab, paste one variable per line in `KEY=value` format. Use the container hostnames for internal services, not public domains:

```
# Postgres
DATABASE_URL=postgresql://myapp_user:<password>@specus-production-database-<suffix>:5432/myapp

# Redis (DB number assigned by infra)
REDIS_URL=redis://:<redis-password>@specus-production-redis-<suffix>:6379/3

# Garage S3
S3_ENDPOINT=https://storage.specus.biz
S3_BUCKET=myapp-uploads
S3_REGION=garage
S3_ACCESS_KEY_ID=<your key>
S3_SECRET_ACCESS_KEY=<your secret>
S3_PUBLIC_BASE_URL=https://cdn.specus.biz/myapp-uploads

# Authentik OAuth2
AUTH_ISSUER=https://auth.specus.biz/application/o/myapp/
AUTH_CLIENT_ID=<your client id>
AUTH_CLIENT_SECRET=<your client secret>
AUTH_REDIRECT_URI=https://myapp.specus.biz/auth/callback

# Your app's own secrets
SECRET_KEY=<openssl rand -base64 42>
```

The exact variable names depend on your framework. What matters is that the hosts and ports match the container hostnames on `dokploy-network`, and that passwords match what the infra team gave you.

Click **Save**.

## Step 5: Deploy

Click **Deploy**. Dokploy clones the repo, builds the image (for Dockerfile services) or pulls it (for image or Compose services), and starts the container attached to `dokploy-network` so it can reach the shared services.

Watch the **Deployments** tab for build logs. When the build finishes, watch the **Logs** tab for your app's startup output. If the app cannot reach Postgres or Redis, the hostname in your env vars is wrong, try the discovery in the "Before you start" section again.

## Step 6: Add a domain

The domain flow has one trap worth knowing about before you start. Let's Encrypt plus Cloudflare proxied DNS is broken by default, and hitting it burns through Let's Encrypt's rate limits (five failures per hostname per hour, lockout lasts up to a week). Do this sequence:

1. In Cloudflare DNS, add an A record:
   - **Type**: A
   - **Name**: `myapp` (for `myapp.specus.biz`)
   - **Target**: the VPS IP (ask infra if you do not know it)
   - **Proxy**: DNS only (grey cloud). Do not enable the orange cloud yet.
2. Verify DNS propagated: `dig +short myapp.specus.biz` should return the VPS IP within a minute.
3. In Dokploy, open your service, **Domains → + Add Domain**:
   - **Domain**: `myapp.specus.biz`
   - **Service/container**: pick your app's container from the dropdown
   - **Container port**: whichever port your app listens on
   - **HTTPS**: enabled (Let's Encrypt)
4. Wait for the cert to issue. A couple of minutes is normal. If Traefik logs show `Certificate obtained`, you are good.
5. Go back to Cloudflare and switch the record to Proxied (orange cloud).

If you want Cloudflare proxied from day one, the alternative is to ask the infra team to configure Traefik's DNS-01 challenge with a Cloudflare API token. That is one-time infra work, not something each service handles on its own.

## Step 7: Smoke test

Open `https://myapp.specus.biz` in your browser. If the page loads, the green path is working. Hit any endpoint that touches the database, cache, S3, and SSO so you know each integration is wired correctly. Do not trust a homepage render as proof that the whole stack works.

## Where to put your secrets

Dokploy stores environment variables encrypted at rest, but that encryption is not a backup. If the Dokploy instance is rebuilt or restored, encrypted values that only live in Dokploy are gone. Keep the source of truth in your team's password manager (1Password, Bitwarden, Vault, SOPS-encrypted file, whatever the team uses). Dokploy is a convenience layer, not the canonical store.

## Where to go next

- Day-to-day operations (redeploy, logs, rollback, troubleshooting): [`dokploy-operations.md`](dokploy-operations.md).
- Patterns for compose services with more than one container: read `authentik/docker-compose.yml` in this repo as a reference, it shows the dual-network pattern used by the platform services.
- Scheduled jobs: talk to whoever owns the Airflow DAGs for your team.
