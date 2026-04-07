# Specus Infrastructure

Custom Docker images for the Specus platform, deployable to Dokploy as individual services.

## Components

| Service | Base Image | Purpose |
|---------|------------|---------|
| PostgreSQL 17 | postgres:17-bookworm | Primary database with extensions |
| Redis 7 | redis:7-alpine | Caching layer |
| Airflow 3.1 | apache/airflow:3.1.7 | Workflow orchestration |
| Garage | dxflrs/garage:v2.2.0 | S3-compatible object storage & CDN |
| Garage WebUI | khairul169/garage-webui:latest | Admin UI for Garage |
| Authentik | ghcr.io/goauthentik/server | Identity provider & SSO |

## Quick Start

### Local Development

```bash
# Build and run all services
cd airflow
docker-compose up -d

# Access services
# PostgreSQL: localhost:5432
# Redis: localhost:6379
# Airflow UI: http://localhost:8080 (admin/admin)
```

### Build Individual Images

```bash
# PostgreSQL
docker build -t specus-postgres:17 ./postgres

# Redis
docker build -t specus-redis:7 ./redis

# Airflow
docker build -t specus-airflow:latest ./airflow

```

## PostgreSQL Extensions

| Extension | Version | Purpose |
|-----------|---------|---------|
| pg_stat_statements | contrib | Query performance monitoring |
| uuid-ossp | contrib | UUID generation |
| pg_trgm | contrib | Fuzzy text search |
| pg_cron | 1.6+ | Job scheduling |
| pg_search | 0.15.6 | BM25 full-text search (ParadeDB) |
| Apache AGE | 1.5.0 | Graph database |
| auto_explain | contrib | Slow query logging |

### Verify Extensions

```sql
SELECT extname, extversion FROM pg_extension ORDER BY extname;
```

## Configuration

### PostgreSQL (4GB RAM optimized)

| Setting | Value | Purpose |
|---------|-------|---------|
| shared_buffers | 1GB | Data caching |
| effective_cache_size | 2GB | Planner hint |
| work_mem | 4MB | Per-operation memory |
| max_connections | 50 | Connection limit |
| log_min_duration_statement | 1000ms | Slow query logging |

### Redis (Cache mode)

| Setting | Value | Purpose |
|---------|-------|---------|
| maxmemory | 256mb | Memory limit |
| maxmemory-policy | allkeys-lru | LRU eviction |
| save | "" | No persistence |
| appendonly | no | No AOF |

### Garage (S3 object storage + CDN)

| Setting | Value | Purpose |
|---------|-------|---------|
| db_engine | lmdb | Metadata storage engine |
| replication_factor | 1 | Single-node (no redundancy) |
| S3 API port | 3900 | Upload/manage objects (storage.procurelens.org) |
| Web gateway port | 3902 | Public CDN (cdn.procurelens.org) |
| Admin API port | 3903 | Bucket/key management (VPN-only) |

## Dokploy Deployment

### 1. Create Services

Create each service in Dokploy as a Docker image deployment:

- **specus-postgres**: `ghcr.io/<username>/specus-postgres:17`
- **specus-redis**: `ghcr.io/<username>/specus-redis:7`
- **specus-airflow-api-server**: `ghcr.io/<username>/specus-airflow:latest`
- **specus-airflow-scheduler**: `ghcr.io/<username>/specus-airflow:latest`
- **specus-airflow-triggerer**: `ghcr.io/<username>/specus-airflow:latest`
- **specus-garage**: Deploy `garage/docker-compose.yml` as a Dokploy compose service (includes Garage + WebUI)
- **specus-authentik**: Deploy `authentik/docker-compose.yml` as a Dokploy compose service (server + worker)

### 2. Network Configuration

Ensure all services are on the same Dokploy network for internal communication.

### 3. Environment Variables

#### PostgreSQL

```
POSTGRES_USER=postgres
POSTGRES_PASSWORD=<secure-password>
POSTGRES_DB=specus
```

#### Redis

```
REDIS_PASSWORD=<secure-password>
```

#### Airflow API Server

```
AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql://airflow:<password>@specus-postgres:5432/airflow
AIRFLOW__CORE__EXECUTOR=LocalExecutor
AIRFLOW__CORE__FERNET_KEY=<generate-with-python>
AIRFLOW__API__SECRET_KEY=<random-hex-string>
AIRFLOW__CORE__LOAD_EXAMPLES=false
_AIRFLOW_WWW_USER_CREATE=true
_AIRFLOW_WWW_USER_USERNAME=admin
_AIRFLOW_WWW_USER_PASSWORD=<secure-password>
```

Command override: `api-server`

#### Garage (via compose `.env`)

Copy `garage/.env.example` to `garage/.env` and fill in values. The compose file handles
wiring between Garage and WebUI automatically.

```
GARAGE_RPC_SECRET=<openssl rand -hex 32>
GARAGE_ADMIN_TOKEN=<openssl rand -hex 32>
GARAGE_METRICS_TOKEN=<openssl rand -hex 32>
GARAGE_WEBUI_AUTH=admin:<bcrypt-hash>
```

Generate bcrypt hash: `htpasswd -nbBC 10 "admin" "your-password"`

#### Authentik (via compose `.env`)

Copy `authentik/.env.example` to `authentik/.env` and fill in values. See `authentik/init-authentik.sql`
for database setup.

```
AUTHENTIK_SECRET_KEY=<openssl rand -base64 60 | tr -d '\n'>
AUTHENTIK_BOOTSTRAP_PASSWORD=<openssl rand -base64 32>
AUTHENTIK_DB_PASSWORD=<openssl rand -base64 32>
REDIS_PASSWORD=<same as core stack>
```

#### Airflow Scheduler

Same environment as API server, with command override: `scheduler`

#### Airflow Triggerer

Same environment as API server, with command override: `triggerer`

### 4. Generate Secrets

```bash
# Fernet key for Airflow encryption
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

# Secret key for Airflow API server
python -c "import secrets; print(secrets.token_hex(32))"

# Generate secure passwords
openssl rand -base64 32

# Garage secrets (hex-encoded)
openssl rand -hex 32

# Garage WebUI password (bcrypt hash)
htpasswd -nbBC 10 "admin" "your-password"
```

### 5. Service Dependencies

Start services in order:
1. PostgreSQL
2. Redis
3. Garage
4. Garage WebUI
5. Airflow Init (runs `airflow db migrate` on first start)
6. Airflow Scheduler
7. Airflow Triggerer
8. Airflow API Server

### 6. Resource Allocation

| Service | Memory Limit | CPU |
|---------|-------------|-----|
| PostgreSQL | 1.5GB | 1 |
| Redis | 300MB | 0.25 |
| Airflow API Server | 768MB | 0.5 |
| Airflow Scheduler | 512MB | 0.5 |
| Airflow Triggerer | 256MB | 0.25 |
| Garage | 256MB | 0.25 |
| Garage WebUI | 128MB | 0.25 |
| Authentik Server | 2GB | 2 |
| Authentik Worker | 1GB | 1 |
| **Total** | **~6.7GB** | **6.0** |

> Airflow parallelism is capped at 8 concurrent tasks to prevent OOM.
> All services have memory limits enforced in docker-compose to prevent OOM cascades.

## CI/CD

Images are automatically built and pushed to GitHub Container Registry on:

- Push to `main` branch (only when relevant files change)
- Manual workflow dispatch

### Registry URLs

```
ghcr.io/<username>/specus-postgres:17
ghcr.io/<username>/specus-redis:7
ghcr.io/<username>/specus-airflow:latest
```

### Manual Build Trigger

Go to Actions tab → Select workflow → Run workflow

### 7. Garage Setup (storage.procurelens.org + cdn.procurelens.org)

After deploying Garage, configure the bucket, DNS, and Dokploy routing:

#### a) Initialize the Garage cluster (once)

```bash
# SSH into VPS, then exec into the Garage container
docker exec -it <garage-container> /bin/sh

# Check node status and copy the node ID
garage status

# Assign storage capacity to the node
garage layout assign <node-id> --zone dc1 --capacity 50G
garage layout apply --version 1
```

#### b) Create bucket and API key

```bash
# Create an API key for the application
garage key create lexicon-app-key

# Create the lexicon bucket
garage bucket create lexicon

# Grant read+write to the app key
garage bucket allow --read --write lexicon --key lexicon-app-key

# Enable public website access
garage bucket website --allow lexicon

# Alias the CDN domain to the bucket (web gateway resolves Host header)
garage bucket alias set --global cdn.procurelens.org lexicon
```

#### c) Cloudflare DNS

| Type | Name | Target | Proxy |
|------|------|--------|-------|
| A | storage | `<server-ip>` | Proxied (orange cloud) |
| A | cdn | `<server-ip>` | Proxied (orange cloud) |

Cloudflare provides SSL termination and caching in front of Traefik.

#### d) Dokploy service — expose S3 API and web gateway

In Dokploy, add **two domains** to the Garage service:

**S3 API (for uploads)**:
- **Domain**: `storage.procurelens.org`
- **Container port**: `3900`
- **HTTPS**: enabled

**Web Gateway (public CDN)**:
- **Domain**: `cdn.procurelens.org`
- **Container port**: `3902`
- **HTTPS**: enabled

Dokploy/Traefik will automatically create the routing labels for both.

#### e) Application .env

```
S3_ENDPOINT=https://storage.procurelens.org
S3_REGION=garage
S3_BUCKET=lexicon
S3_ACCESS_KEY_ID=<from garage key create>
S3_SECRET_ACCESS_KEY=<from garage key create>
S3_PUBLIC_BASE_URL=https://cdn.procurelens.org/lexicon
```

Public URLs in CMS content: `https://cdn.procurelens.org/lexicon/uploads/image/{uuid}/{file.png}`

## Monitoring

### PostgreSQL

```sql
-- Slow queries
SELECT * FROM slow_queries;

-- Database sizes
SELECT * FROM database_sizes;

-- Active connections
SELECT count(*) FROM pg_stat_activity WHERE state = 'active';
```

### Redis

```bash
# Memory usage
redis-cli INFO memory

# Slow queries
redis-cli SLOWLOG GET 10

# Key statistics
redis-cli INFO keyspace
```

### Garage

Access the Garage WebUI at `http://<vps-ip>:3909` (VPN-only) for bucket/key management.

```bash
# Cluster status
garage status

# Bucket info
garage bucket info lexicon

# List API keys
garage key list

# Storage stats
garage stats
```

### Airflow

Access the web UI at your configured domain or `http://localhost:8080` for local development.

## Security Notes

1. **Never commit passwords** - Use environment variables in Dokploy
2. **PostgreSQL uses scram-sha-256** - Most secure password authentication
3. **Redis requires password** - Protected mode is enabled
4. **Airflow uses Fernet encryption** - Connections are encrypted at rest
5. **Garage secrets via env vars** - RPC secret, admin token, and metrics token are never stored in config files
6. **Garage S3 API is authenticated** - Public via `storage.procurelens.org` but requires S3 access key + secret (SigV4 signing). Web gateway (`cdn.procurelens.org`) is read-only CDN. Admin API (3903) and WebUI (3909) are VPN-only.
7. **Authentik via Traefik only** - No direct port exposure; rate-limited at 100 req/min via Traefik middleware
8. **GHCR tokens** - Use minimal permissions for CI/CD

## Directory Structure

```
infrastructure/
├── .github/workflows/     # CI/CD pipelines
├── postgres/
│   ├── Dockerfile         # Multi-stage build with extensions
│   ├── .env.example       # PostgreSQL + role passwords
│   ├── postgresql.conf    # Production configuration
│   ├── pg_hba.conf        # Authentication rules
│   └── init-scripts/      # Database initialization
├── redis/
│   ├── Dockerfile              # Alpine-based image
│   ├── .env.example            # Redis password
│   ├── specus-redis-entrypoint.sh  # Password injection entrypoint
│   └── redis.conf              # Cache configuration
├── airflow/
│   ├── Dockerfile         # Custom Airflow image
│   ├── .env.example       # Airflow secrets + references to PG/Redis
│   ├── docker-compose.yml # Local development
│   ├── airflow.cfg        # Airflow configuration
│   └── dags/              # DAG files
├── garage/
│   ├── docker-compose.yml # Garage + WebUI (Dokploy compose)
│   ├── .env.example       # Garage + WebUI secrets
│   └── garage.toml        # Storage & web gateway configuration
├── authentik/
│   ├── docker-compose.yml        # Server + Worker (Dokploy compose)
│   ├── .env.example              # All Authentik config
│   ├── init-authentik.sql        # Database initialization
│   └── traefik-config.example.yml # Traefik reference
└── README.md
```

## License

Private - Specus Platform
