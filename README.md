# Specus Infrastructure

Custom Docker images for the Specus platform, deployable to Dokploy as individual services.

## Components

| Service | Base Image | Purpose |
|---------|------------|---------|
| PostgreSQL 17 | postgres:17-bookworm | Primary database with extensions |
| Redis 7 | redis:7-alpine | Caching layer |
| Airflow 3.1 | apache/airflow:3.1.7 | Workflow orchestration |

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

## Dokploy Deployment

### 1. Create Services

Create each service in Dokploy as a Docker image deployment:

- **specus-postgres**: `ghcr.io/<username>/specus-postgres:17`
- **specus-redis**: `ghcr.io/<username>/specus-redis:7`
- **specus-airflow-api-server**: `ghcr.io/<username>/specus-airflow:latest`
- **specus-airflow-scheduler**: `ghcr.io/<username>/specus-airflow:latest`
- **specus-airflow-triggerer**: `ghcr.io/<username>/specus-airflow:latest`

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
```

### 5. Service Dependencies

Start services in order:
1. PostgreSQL
2. Redis
3. Airflow Init (runs `airflow db migrate` on first start)
4. Airflow Scheduler
5. Airflow Triggerer
6. Airflow API Server

### 6. Resource Allocation (4GB server)

| Service | Memory Limit | CPU |
|---------|-------------|-----|
| PostgreSQL | 1.5GB | 1 |
| Redis | 300MB | 0.25 |
| Airflow API Server | 768MB | 0.5 |
| Airflow Scheduler | 512MB | 0.5 |
| Airflow Triggerer | 256MB | 0.25 |
| **Total** | **~3.3GB** | **2.5** |

> Remaining ~700MB is reserved for the OS, Docker daemon, and page cache.
> Airflow parallelism is capped at 8 concurrent tasks to prevent OOM.
> All services have `mem_limit` enforced in docker-compose to prevent OOM cascades.

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

### Airflow

Access the web UI at your configured domain or `http://localhost:8080` for local development.

## Security Notes

1. **Never commit passwords** - Use environment variables in Dokploy
2. **PostgreSQL uses scram-sha-256** - Most secure password authentication
3. **Redis requires password** - Protected mode is enabled
4. **Airflow uses Fernet encryption** - Connections are encrypted at rest
5. **GHCR tokens** - Use minimal permissions for CI/CD

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
└── README.md
```

## License

Private - Specus Platform
