# Dokploy Operations

Day-two reference for the Specus infrastructure stack on Dokploy. Complements [`dokploy-first-deploy.md`](dokploy-first-deploy.md), which covers first-time setup.

## How Dokploy works for this stack

Deploys are UI-driven. Environment variables live in Dokploy's encrypted store, not in the repo. Generated container hostnames (the `specus-production-*-<suffix>` pattern) are unique to your installation and live in env vars.

Most services in this repo are deployed as Dokploy Compose services. Postgres and Redis are deployed as Application services with a Dockerfile. Airflow is deployed as three separate Application services sharing one Dockerfile, each with a different `command` override (this is a Dokploy feature on Application services; compose services set the command in the file).

Resource limits for Compose services must be set in the compose file (`deploy.resources.limits`). Dokploy's UI cannot override them. For Application services, resource limits can be set in the UI.

## Common operations

**Redeploy after a code change**. Push to `main`, then in Dokploy click **Deploy** on the service. Or enable **Auto-deploy** in the service settings so pushes trigger a rebuild via webhook. Auto-deploy fires on any push to the tracked branch, including force-pushes and docs-only commits, so use it on staging freely and be deliberate about turning it on for production.

**View live logs**. The **Logs** tab shows each container's stdout/stderr in real time. For Compose services with multiple containers, pick which one. Use the filter box for keywords.

**Exec into a container**. The **Terminal** tab gives a shell inside the running container. Useful for `psql -U postgres -d specus`, `redis-cli -a $REDIS_PASSWORD`, and running service-specific CLI commands (for example `ak` for Authentik). Terminal access is the same trust level as Docker group access on the host, which is effectively root. Restrict who has Dokploy project access accordingly.

**Update an environment variable**. The **Environment** tab. Edit, save, then click **Deploy** for the change to take effect. Changes are not picked up until the container restarts. Do not edit while an active deploy is running.

**Rollback a bad deploy**. The **Deployments** tab lists past deployments. Pick the last working one and click **Rollback**. Dokploy redeploys the previous image or commit. What rollback does and does not cover:

- Covers: application code, container image, build output
- Does not cover: database migrations already applied, environment variable changes, volume state, data that has been written since the bad deploy

For stateful services (Postgres, Authentik metadata DB), rollback a forward migration by rolling back the database separately. Take a `pg_dump` before any deploy that includes a new migration. Test your rollback procedure on staging before you need it.

**Scale resources**. Application services have an **Advanced → Resources** tab for CPU and memory limits. Compose services have to change the limits in the compose file, commit, push, and redeploy.

## Troubleshooting

| What you see | Likely cause | What to do |
|---|---|---|
| `ErrImagePull` during deploy | Wrong image path, registry auth failure, or for custom images the build step never ran | Check build logs in the Deployments tab |
| 404 from the public domain | Traefik has no route for this hostname, or the domain's target container name or port is wrong | Re-check the Domains tab. The container name in the dropdown is the compose service key (for Authentik that is `authentik-server`), not the `container_name` field. Port must match what the container actually listens on |
| 502 Bad Gateway from the public domain | Container is up but not listening on the port Dokploy expects, or the container is still starting | Exec into the container, `curl localhost:<port>/health`. If that fails, the app has not finished booting or is crashing |
| Let's Encrypt cert will not issue | Usually because Cloudflare is proxied (orange cloud) before the first cert was issued, which breaks HTTP-01 validation. Let's Encrypt rate-limits after 5 failures per hostname per hour and the lockout can last up to a week | Set the DNS record to grey cloud (DNS only), wait for validation, then switch to orange cloud. Check Dokploy has a Let's Encrypt email set in Settings. If you have already hit the rate limit, wait or switch to DNS-01 challenge with a Cloudflare API token |
| Service can not reach Postgres or Redis | Env var points at the wrong generated hostname suffix | Run `docker network inspect dokploy-network --format '{{range .Containers}}{{.Name}}{{println}}{{end}}'` on the VPS, update the consumer service's env vars, redeploy |
| Container OOM-killed (`Exit 137`) | Memory limit is lower than the service actually needs | For Application services, bump the limit in Advanced → Resources. For Compose services, edit `deploy.resources.limits.memory` in the compose file, push, redeploy |
| Disk full | Docker accumulating dead images, volumes, build cache | On the VPS, `docker system prune -a --volumes`. Do not delete named volumes attached to running services. Run this monthly |
| Deploy fails because ports are in use | Something outside Dokploy is bound to 80, 443, or 3000 | `sudo ss -tlnp` on the VPS to find the culprit |
| Compose file not found | Wrong Compose path in the service config | Path is relative to repo root, include the filename. Example: `./authentik/docker-compose.yml` |

### When the UI cannot tell you what is wrong

Fall back to the VPS shell:

- `docker ps -a` shows every container including exited ones
- `docker logs <container>` shows the full log history
- `docker network inspect dokploy-network` shows every attached container and its IP
- `docker exec -it <container> sh` is a direct shell when the Dokploy Terminal tab is unresponsive

## Service deploy reference

| Service | Dokploy type | Compose/Dockerfile path | Depends on | Public domain |
|---|---|---|---|---|
| `specus-production-database` | Application (Dockerfile) | `./postgres` | nothing | none |
| `specus-production-redis` | Application (Dockerfile) | `./redis` | nothing | none |
| `specus-production-garage` | Compose | `./garage/docker-compose.yml` | nothing | `storage.specus.biz` (port 3900), `cdn.specus.biz` (port 3902) |
| `specus-production-airflow-api-server` | Application (Dockerfile, command override: `api-server`) | `./airflow` | Postgres | `airflow.specus.biz` (port 8080) through VPN only |
| `specus-production-airflow-scheduler` | Application (Dockerfile, command override: `scheduler`) | `./airflow` | Postgres | none |
| `specus-production-airflow-triggerer` | Application (Dockerfile, command override: `triggerer`) | `./airflow` | Postgres | none |
| `specus-production-authentik` | Compose | `./authentik/docker-compose.yml` | Postgres, Redis, Garage | `auth.specus.biz` (container `authentik-server`, port 9000) |

For each service, `.env.example` in its directory lists every required variable with a generation command. The golden rule: if you see `${FOO}` in a compose file or Dockerfile, it is in `.env.example`.

### Airflow's three services

Airflow is the unusual one. Three separate Dokploy Application services share one Dockerfile (`airflow/Dockerfile`) and one base environment. The difference is the Docker `CMD` override in each service's Advanced tab:

- `api-server` runs the webserver and API
- `scheduler` runs the DAG scheduler
- `triggerer` runs async task triggers

All three use `LocalExecutor`, so Airflow does not need Celery or Redis. All three read from the same metadata database in Postgres.

The `airflow/docker-compose.yml` file in the repo is for local development only. Do not deploy it to Dokploy as a compose service.

## Backups and retention

Dokploy does not back up your data. Set up your own. Minimum viable:

- **Postgres**: scheduled `pg_dump` to Garage or an external object store. A daily dump plus point-in-time recovery via WAL archiving is standard for the shared metadata DB.
- **Garage**: replicate the `specus` bucket to an external S3 on a schedule. Alternatively, snapshot the Garage data volume from the VPS provider.
- **Dokploy state**: the `/var/lib/dokploy` volume holds Dokploy's own DB, encrypted env vars, and state. Snapshot this volume weekly.
- **Secrets**: your out-of-Dokploy password manager is the authority. Dokploy's encrypted-at-rest storage is not a backup.

## Updates

Dokploy itself: check the [Dokploy release notes](https://github.com/Dokploy/dokploy/releases) monthly. Update via Settings when a security patch ships.

Base images (Postgres, Redis, Traefik, Authentik, anything pinned to a specific tag): `unattended-upgrades` on the host does not update Docker images. Rebuild and redeploy services monthly so you pick up base image CVE fixes.

Service-specific image upgrades (for example bumping Authentik from `2026.2.1` to the next release) need a read-through of the upstream changelog. Migrations run on first boot and are rarely reversible.

## Security boundaries to remember

- Dokploy admin + anyone with Terminal tab access + anyone in the Docker group = effective root on the host.
- Environment variables are visible in plaintext to anyone who opens the Environment tab. Be careful about screen-sharing.
- Any port you add to a compose file's `ports:` section is exposed to the internet by Docker, bypassing `ufw` if `ufw` is your only firewall. The cloud-provider firewall is the enforcement layer. Do not use `ports:` for debugging without understanding this.
- Never create a Cloudflare DNS record for Postgres, Redis, Airflow UI, or Garage admin ports. These are VPN-only services. The only public Cloudflare records in this setup are `auth`, `storage`, `cdn`, and `vpn` subdomains.
- The Authentik bootstrap password must be removed from the Environment tab after first login, otherwise every redeploy re-ingests it.

## Deleting things

Do not delete Dokploy services casually. Deleting a service removes its container, but volumes attached by name persist. Deleting volumes in Dokploy is destructive and not reversible. For stateful services, always take a backup first.

`docker system prune` and `docker volume prune` can wipe volumes that are not attached to a running container. Do not run prune while a service is stopped temporarily.
