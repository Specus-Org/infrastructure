# Operating Your Service on Dokploy

Day-to-day operations reference for a service you deployed onto the Specus infrastructure. Complements [`dokploy-first-deploy.md`](dokploy-first-deploy.md), which covers the initial setup of a new service.

## How Dokploy works, from your seat

Your service lives in a Dokploy project. You can redeploy it, read its logs, shell into its container, edit its environment variables, and roll it back. You do not control the shared platform services (Postgres, Redis, Garage, Authentik) and you do not control the host itself. If you need something from those, talk to the infra team.

Your service joins `dokploy-network` at deploy time, which is how it reaches the shared services. Hostnames on this network are the Dokploy-generated container names (for example `specus-production-database-rkpsij`), not the public `.specus.biz` domains.

Environment variables live in Dokploy's encrypted store. They are displayed in plaintext in the Environment tab when you open it, so watch what you share on screen.

## Common operations

**Redeploy after a code change**. Push to the branch Dokploy is tracking, then click **Deploy** on the service. Or enable **Auto-deploy** in the service settings so pushes trigger a rebuild automatically. Auto-deploy fires on every push to the tracked branch, including force-pushes and docs-only commits, so use it freely on staging and consciously on production.

**Read live logs**. The **Logs** tab streams each container's stdout/stderr. For Compose services with more than one container, pick which one. The filter box helps when a deploy is chatty.

**Shell into a container**. The **Terminal** tab gives a shell inside the running container. Useful for running your framework's CLI (migrations, seeds, one-off scripts) or for quick debugging. Do not use the Terminal to change files that the image builds from, those changes are gone on the next redeploy.

**Update an environment variable**. The **Environment** tab. Edit, save, then click **Deploy** so the container restarts and picks up the change. Changes are not applied live.

**Rollback a bad deploy**. The **Deployments** tab lists every past deployment. Pick the last working one and click **Rollback**. Rollback covers the application code and image. It does not cover database migrations already applied, environment variable changes, or data that was written since the bad deploy. If your bad deploy ran a forward-migration that the old code cannot read, you will need to roll back the database separately. Take a `pg_dump` or equivalent before any risky deploy.

**Scale resources**. For Application services, the **Advanced → Resources** tab exposes CPU and memory limits. For Compose services, limits live in the `deploy.resources.limits` block of your compose file, edit-commit-push-redeploy to change them.

## Troubleshooting

| What you see | Likely cause | What to do |
|---|---|---|
| `ErrImagePull` during deploy | Image path wrong, registry auth failure, or for custom images the build step never ran | Check the Deployments tab build logs. If you build from Dockerfile, verify the build context path and Dockerfile name. If you pull from a registry, verify the image tag exists |
| 404 from your public domain | Traefik has no route, or the container name or port in the Domains tab is wrong | Open the Domains tab. The container name must match a running container. The port must match what your app actually listens on inside the container |
| 502 Bad Gateway | Container is up but not listening on the port Dokploy expects, or the app is still starting | Shell into the container and `curl localhost:<port>/health`. If that fails, your app has not finished booting or is crashing after a moment. Read the logs |
| Let's Encrypt cert will not issue | Usually Cloudflare proxy (orange cloud) is enabled before the first cert was issued, which breaks HTTP-01 validation | Switch the DNS record to grey cloud (DNS only), wait for Traefik to issue the cert, then switch back to orange cloud. Rate limit is five failures per hostname per hour, up to a one-week lockout, so do not just hammer redeploy |
| App cannot reach Postgres or Redis | Your env var points at the wrong generated container hostname | Look up the current hostname in the Dokploy UI (General tab of the Postgres or Redis service) or ask the infra team. Update your env var and redeploy |
| Cannot reach Garage S3 | `S3_ENDPOINT` points somewhere wrong, or your S3 credentials are not on the bucket | `S3_ENDPOINT=https://storage.specus.biz` is the public endpoint. If you get 403, the access key does not have rights on the bucket, ask infra to fix the grant |
| Authentik OAuth2 fails | Redirect URI mismatch between what your app sends and what is registered in Authentik, or the OAuth2 client secret is wrong | In the browser devtools Network tab, check the `redirect_uri` query parameter being sent. It must match exactly what was registered. Protocol, subdomain, path, trailing slash, all exact |
| Container OOM-killed (`Exit 137`) | Memory limit is lower than the service actually needs | Check `docker stats` or Dokploy's Monitoring tab for actual usage. Bump the limit in Advanced → Resources (Application) or in the compose file (Compose) |
| Deploy looks stuck | Build is running, just slow; or the build is waiting on a cache miss; or Dokploy is trying to pull a large image | Give it a few minutes. If still stuck after ten, check the Deployments tab for the running build's logs |

When the UI does not tell you what is wrong, the logs usually do. Read them top to bottom, not just the last screen.

## What you should not do

- **Do not modify the shared infrastructure**. Postgres, Redis, Garage, and Authentik are managed by the infra team. Changes there affect every service on the platform. If you need a new Postgres extension, a bigger Redis, or a new Authentik OAuth2 client, file a request, do not shell into the Postgres container and install things yourself.
- **Do not add `ports:` to your compose file for debugging.** Docker inserts iptables rules that bypass the host firewall, so `ports:` effectively exposes that port to the public internet regardless of `ufw` rules. Use the Dokploy Terminal tab instead.
- **Do not create public Cloudflare DNS records for Postgres, Redis, Airflow UI, or Garage admin ports**. These are VPN-only services. Public DNS records for them would expose them to the internet, which is a security incident.
- **Do not commit `.env` files.** Keep the source of truth in a password manager. Dokploy's Environment tab is a runtime store, not a backup.
- **Do not delete a Dokploy service without a plan for volumes.** Deleting a service removes the container. Attached named volumes may persist or may not, depending on how the service was configured. For stateful services, always snapshot or dump first.

## Where the platform's limits will bite you

- **Postgres connection budget**. The shared Postgres has a fixed `max_connections`. If your app opens a large connection pool under load, you can starve other services. Set a reasonable pool size (ask infra what fits the current budget) and make sure your app reuses connections.
- **Redis memory**. The shared Redis is 512 MB with LRU eviction. Your cache keys can be evicted under memory pressure. Cache intentionally (with TTLs and sensible key sizes), not defensively.
- **Garage bandwidth**. The Garage CDN fronts uploads behind Cloudflare. Very large files or hot traffic may need a content-delivery strategy beyond raw Garage.
- **Authentik session state**. Authentik stores sessions in Redis DB 1. Rotating its Fernet key or `SUPERSET_SECRET_KEY`-class values in other services destroys session data, so plan rotation carefully.

## Where to ask for help

If you hit something this doc does not cover, the infra team is the right escalation path. Before you ask, have ready:
- The Dokploy service name
- The error message or symptom, verbatim
- The deployment timestamp you think things started going wrong
- What you already tried

That gets you an answer faster than "it is broken."
