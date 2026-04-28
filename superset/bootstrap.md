# Superset First-Deploy Runbook

Step-by-step instructions for bringing up a fresh Superset deployment on Dokploy.
Follow in order — most steps only need to happen once.

---

## Prerequisites

- Core stack is running: PostgreSQL (`specus-production-database-rkpsij`) and Redis (`specus-production-redis-h08jhy`) are healthy.
- You have a SQL client (DBeaver or psql) that can reach the shared Postgres.
- `.env` is filled in: `cp .env.example .env` then set all required values.
- The Dokploy service is wired to this repo so `superset_config.py` lands on the host next to `docker-compose.yml` (the compose bind-mounts it into every container).

---

## Step 1: Bootstrap the metadata database

Connect to the shared Postgres with a superuser and run `init-superset.sql` in two parts:

1. **Connected to `postgres` database** — run Step 1 block (creates `superset` DB, `superset_user`, transfers ownership, revokes cross-DB connect).
2. **Switch connection to `superset` database** — Step 2 is a no-op for the default setup (ownership transfer in Step 1 covers the schema). Only uncomment the grants if migrations will run as a different role.

Replace `CHANGE_ME_SECURE_PASSWORD` with the value of `SUPERSET_DB_PASSWORD` from your `.env`.

---

## Step 2: Start the containers

```bash
docker-compose --env-file .env up -d
```

The `superset-init` service runs first and blocks on `superset db upgrade && superset init`. The web and worker containers only start after it exits successfully, and Beat also waits for the `superset-beat-permissions` one-shot to make its schedule volume writable by the `superset` user.

Wait until the three long-running containers are `healthy`:

```bash
docker-compose --env-file .env ps
```

`superset-init` and `superset-beat-permissions` will show status `Exit 0` — that's expected.

---

## Step 3: Create the admin user

*One-shot — running this with different values creates a second admin.*

Pass the password via stdin instead of `--password` so it never lands in shell history, the Docker daemon log, or `ps auxww`:

```bash
printf '%s\n' "$SUPERSET_ADMIN_PASSWORD" | \
  docker exec -i specus-superset-web superset fab create-admin \
    --username "$SUPERSET_ADMIN_USERNAME" \
    --firstname "$SUPERSET_ADMIN_FIRSTNAME" \
    --lastname "$SUPERSET_ADMIN_LASTNAME" \
    --email "$SUPERSET_ADMIN_EMAIL"
```

Export the `SUPERSET_ADMIN_*` variables in your shell for this one command only — do **not** commit them to `.env`. See `.env.example` § Admin Bootstrap for suggested values.

After the admin is created, clear the password from your shell: `unset SUPERSET_ADMIN_PASSWORD`.

---

## Step 4: Register the specus Postgres data source

1. Log in to `https://superset.specus.biz` with the admin credentials.
2. Confirm the read-only Postgres role exists. Fresh Postgres deployments create it from `postgres/init-scripts/03-superset-readonly.sh` when `SUPERSET_READONLY_PASSWORD` is set in `postgres/.env`.

   For an existing Postgres volume, run the same script once after deploying an image that contains it:
   ```bash
   export SUPERSET_READONLY_PASSWORD='<generate-with-openssl-rand>'
   POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep '^specus-production-database-rkpsij' | head -1)
   docker exec -e SUPERSET_READONLY_PASSWORD="$SUPERSET_READONLY_PASSWORD" \
     "$POSTGRES_CONTAINER" \
     /docker-entrypoint-initdb.d/03-superset-readonly.sh
   ```
3. In Superset: **Settings → Database Connections → + Database → PostgreSQL**.
4. Enter the SQLAlchemy URI:
   ```
   postgresql+psycopg2://superset_readonly:<SUPERSET_READONLY_PASSWORD>@specus-production-database-rkpsij:5432/specus
   ```
5. Click **Test Connection** → **Connect**.
6. On the connection's **Advanced → Security** tab, confirm **Allow DML** is off. Superset's `PREVENT_UNSAFE_DB_CONNECTIONS=True` (set in `superset_config.py`) is the belt — this checkbox is the braces.

---

## Step 5: Smoke test

1. Navigate to **SQL Lab**.
2. Select the `specus` database.
3. Run: `SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';`
4. Click **Run** (default is synchronous; switch to async with the toggle and run again).
5. Confirm both sync and async modes return results. Async proves the full web → broker → worker → results-backend chain is wired correctly.

---

## Step 6: Dokploy + Cloudflare routing

In Dokploy, add a domain to the Superset **compose service**:

- **Domain**: `superset.specus.biz`
- **Service/container**: `superset-web`
- **Container port**: `8088`
- **HTTPS**: enabled

In Cloudflare DNS, add:

| Type | Name | Target | Proxy |
|------|------|--------|-------|
| A | superset | `<server-ip>` | Proxied (orange cloud) |

---

## Redeployment checklist

On subsequent deploys (config change, Superset version bump):

1. Pull new image: `docker-compose --env-file .env pull`
2. Restart: `docker-compose --env-file .env up -d`
3. `superset-init` runs again automatically and re-applies any new migrations. `superset db upgrade` and `superset init` are both idempotent, so this is safe.
4. **Do NOT re-run the admin creation command** unless you intend to create a second admin.

---

## Rotating `SUPERSET_SECRET_KEY`

**Warning:** `SUPERSET_SECRET_KEY` is the Fernet key Superset uses to encrypt the stored passwords of all registered data source connections (the `dbs.password` column in the metadata DB). Rotating it without the re-encryption dance below will brick every data source — SQL Lab queries and scheduled reports will fail with `InvalidToken` errors and you will have to re-enter every connection password by hand.

Safe rotation:

1. Set the current key as `PREVIOUS_SECRET_KEY` and the new key as `SUPERSET_SECRET_KEY` in `.env`.
2. Add this to the top of `superset_config.py` (temporary):
   ```python
   PREVIOUS_SECRET_KEY = os.environ["PREVIOUS_SECRET_KEY"]
   ```
3. `docker-compose --env-file .env up -d` (containers restart with both keys available).
4. Re-encrypt existing secrets:
   ```bash
   docker exec specus-superset-web superset re-encrypt-secrets
   ```
5. Remove `PREVIOUS_SECRET_KEY` from `.env` and the config, restart once more.

If you skip this dance, the only recovery path is re-entering every data source credential via the Superset UI.
