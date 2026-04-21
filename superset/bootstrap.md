# Superset First-Deploy Runbook

Step-by-step instructions for bringing up a fresh Superset deployment on Dokploy.
Follow in order — most steps only need to happen once.

---

## Prerequisites

- Core stack is running: PostgreSQL (`specus-production-database-rkpsij`) and Redis (`specus-production-redis-h08jhy`) are healthy.
- You have a SQL client (DBeaver or psql) that can reach the shared Postgres.
- `.env` is filled in: `cp .env.example .env` then set all required values.
- The `specus-superset` image has been pushed to GHCR by CI (or built locally).

---

## Step 1: Bootstrap the metadata database

Connect to the shared Postgres with a superuser and run `init-superset.sql` in two parts:

1. **Connected to `postgres` database** — run Step 1 block (creates `superset` DB and `superset_user`).
2. **Switch connection to `superset` database** — run Step 2 block (grants schema privileges).

Replace `CHANGE_ME_SECURE_PASSWORD` with the value of `SUPERSET_DB_PASSWORD` from your `.env`.

---

## Step 2: Start the containers

```bash
docker-compose --env-file .env up -d
```

Wait until all three containers are `healthy`:

```bash
docker-compose --env-file .env ps
```

---

## Step 3: Run database migrations

*Safe to re-run on redeploys.*

```bash
docker exec specus-superset-web superset db upgrade
```

---

## Step 4: Create the admin user

*One-shot — running this twice with different values creates two admins.*

```bash
docker exec -it specus-superset-web superset fab create-admin \
  --username admin \
  --firstname Admin \
  --lastname User \
  --email admin@specus.biz \
  --password YOUR_ADMIN_PASSWORD
```

Use the values from your `.env` (`SUPERSET_ADMIN_*`).

---

## Step 5: Initialize roles and permissions

*Safe to re-run on redeploys or after upgrading Superset.*

```bash
docker exec specus-superset-web superset init
```

---

## Step 6: Register the specus Postgres data source

1. Log in to `https://superset.specus.biz` with the admin credentials.
2. Navigate to **Settings → Database Connections → + Database**.
3. Select **PostgreSQL**.
4. Enter the SQLAlchemy URI:
   ```
   postgresql+psycopg2://<user>:<password>@specus-production-database-rkpsij:5432/specus
   ```
   Use a dedicated read-only role on the `specus` database (create one with `CREATE USER specus_readonly WITH ENCRYPTED PASSWORD '...'; GRANT CONNECT ON DATABASE specus TO specus_readonly; GRANT USAGE ON SCHEMA public TO specus_readonly; GRANT SELECT ON ALL TABLES IN SCHEMA public TO specus_readonly; ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO specus_readonly;`).
5. Click **Test Connection** → **Connect**.

---

## Step 7: Smoke test

1. Navigate to **SQL Lab**.
2. Select the `specus` database.
3. Run: `SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';`
4. Confirm the query completes asynchronously (result arrives via Celery worker).

---

## Step 8: Dokploy + Cloudflare routing

In Dokploy, add a domain to the Superset **compose service**:

- **Domain**: `superset.specus.biz`
- **Service/container**: `superset-web`
- **Container port**: `8088`
- **HTTPS**: enabled

In Cloudflare DNS, add:

| Type | Name | Target | Proxy |
|------|------|--------|-------|
| A | bi | `<server-ip>` | Proxied (orange cloud) |

---

## Redeployment checklist

On subsequent deploys (image update, config change):

1. Pull new image: `docker-compose --env-file .env pull`
2. Restart: `docker-compose --env-file .env up -d`
3. Run migrations: `docker exec specus-superset-web superset db upgrade` *(idempotent)*
4. Re-init roles: `docker exec specus-superset-web superset init` *(idempotent)*
5. **Do NOT re-run `fab create-admin`** unless you intend to create a second admin.
