# Specus Infrastructure

Custom Docker images for the Specus platform, deployable to Dokploy as individual services.

## Components

| Service | Base Image | Purpose |
|---------|------------|---------|
| PostgreSQL 17 | postgres:17-bookworm | Primary database with extensions |
| Redis 7 | redis:7-alpine | Caching layer |
| Airflow 2.10 | apache/airflow:2.10.4 | Workflow orchestration |

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
| shared_buffers | 256MB | Data caching |
| effective_cache_size | 768MB | Planner hint |
| work_mem | 16MB | Per-operation memory |
| max_connections | 100 | Connection limit |
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
- **specus-airflow-webserver**: `ghcr.io/<username>/specus-airflow:latest`
- **specus-airflow-scheduler**: `ghcr.io/<username>/specus-airflow:latest`

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
# Pass password via command override
Command: redis-server /usr/local/etc/redis/redis.conf --requirepass <secure-password>
```

#### Airflow Webserver

```
AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql://airflow:<password>@specus-postgres:5432/airflow
AIRFLOW__CORE__EXECUTOR=LocalExecutor
AIRFLOW__CORE__FERNET_KEY=<generate-with-python>
AIRFLOW__WEBSERVER__SECRET_KEY=<random-hex-string>
AIRFLOW__CORE__LOAD_EXAMPLES=false
_AIRFLOW_WWW_USER_CREATE=true
_AIRFLOW_WWW_USER_USERNAME=admin
_AIRFLOW_WWW_USER_PASSWORD=<secure-password>
```

Command override: `webserver`

#### Airflow Scheduler

Same environment as webserver, with command override: `scheduler`

### 4. Generate Secrets

```bash
# Fernet key for Airflow encryption
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

# Secret key for Airflow webserver
python -c "import secrets; print(secrets.token_hex(32))"

# Generate secure passwords
openssl rand -base64 32
```

### 5. Service Dependencies

Start services in order:
1. PostgreSQL
2. Redis
3. Airflow Scheduler (runs `airflow db migrate` on first start)
4. Airflow Webserver

### 6. Resource Allocation

| Service | Memory | CPU |
|---------|--------|-----|
| PostgreSQL | 1GB | 1 |
| Redis | 256MB | 0.5 |
| Airflow Webserver | 512MB | 0.5 |
| Airflow Scheduler | 512MB | 0.5 |

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
│   ├── postgresql.conf    # Production configuration
│   ├── pg_hba.conf        # Authentication rules
│   └── init-scripts/      # Database initialization
├── redis/
│   ├── Dockerfile         # Alpine-based image
│   └── redis.conf         # Cache configuration
├── airflow/
│   ├── Dockerfile         # Custom Airflow image
│   ├── docker-compose.yml # Local development
│   ├── airflow.cfg        # Airflow configuration
│   └── dags/              # DAG files
└── README.md
```

## License

Private - Specus Platform
