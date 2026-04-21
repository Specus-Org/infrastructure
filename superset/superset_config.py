import os
from urllib.parse import quote

from cachelib.redis import RedisCache
from celery.schedules import crontab
from flask_appbuilder.security.manager import AUTH_DB


def _require(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(
            f"{name} is not set. "
            f"See superset/.env.example for the generation command."
        )
    return value


# =============================================================================
# SECURITY
# =============================================================================

SECRET_KEY = _require("SUPERSET_SECRET_KEY")

# =============================================================================
# METADATA DATABASE
# =============================================================================

_db_user = quote(_require("SUPERSET_DB_USER"), safe="")
_db_pass = quote(_require("SUPERSET_DB_PASSWORD"), safe="")
_db_host = os.environ.get("POSTGRES_HOST", "specus-production-database-rkpsij")
_db_port = os.environ.get("POSTGRES_PORT", "5432")
_db_name = os.environ.get("SUPERSET_DB_NAME", "superset")

SQLALCHEMY_DATABASE_URI = (
    f"postgresql+psycopg2://{_db_user}:{_db_pass}@{_db_host}:{_db_port}/{_db_name}"
)

# Pool sized assuming SERVER_WORKER_AMOUNT=4 in compose: 4 × (pool+overflow) = 24
# metadata DB conns per web container, plus 1 worker × (pool+overflow) = 6. Total
# stays under the shared-Postgres budget (max_connections=50) with headroom for
# Airflow + Authentik. Bump only if Postgres max_connections is raised globally.
SQLALCHEMY_POOL_SIZE = 3
SQLALCHEMY_MAX_OVERFLOW = 3
SQLALCHEMY_POOL_TIMEOUT = 30
SQLALCHEMY_POOL_RECYCLE = 3600
SQLALCHEMY_POOL_PRE_PING = True

# =============================================================================
# REDIS (cache DB 2, broker DB 3, results DB 4)
# =============================================================================

_redis_host = os.environ.get("REDIS_HOST", "specus-production-redis-h08jhy")
_redis_port = os.environ.get("REDIS_PORT", "6379")
_redis_pass_raw = os.environ.get("REDIS_PASSWORD", "")
_redis_pass = quote(_redis_pass_raw, safe="") if _redis_pass_raw else ""
_redis_auth = f":{_redis_pass}@" if _redis_pass else ""

_redis_cache_db = os.environ.get("SUPERSET_CACHE_REDIS_DB", "2")
_redis_broker_db = os.environ.get("SUPERSET_CELERY_BROKER_DB", "3")
_redis_results_db = os.environ.get("SUPERSET_CELERY_RESULT_DB", "4")

_redis_cache_url = f"redis://{_redis_auth}{_redis_host}:{_redis_port}/{_redis_cache_db}"
_redis_broker_url = f"redis://{_redis_auth}{_redis_host}:{_redis_port}/{_redis_broker_db}"
_redis_results_url = f"redis://{_redis_auth}{_redis_host}:{_redis_port}/{_redis_results_db}"

# =============================================================================
# CACHE
# =============================================================================

def _redis_cache(prefix: str, timeout: int) -> dict:
    return {
        "CACHE_TYPE": "RedisCache",
        "CACHE_DEFAULT_TIMEOUT": timeout,
        "CACHE_KEY_PREFIX": prefix,
        "CACHE_REDIS_URL": _redis_cache_url,
    }


# Short TTL on the app/session cache; longer on data/filter/explore caches since
# those are keyed to query hashes and are safe to serve stale until invalidation.
CACHE_CONFIG = _redis_cache("superset_", 300)
DATA_CACHE_CONFIG = _redis_cache("superset_data_", 3600)
FILTER_STATE_CACHE_CONFIG = _redis_cache("superset_filter_", 3600)
EXPLORE_FORM_DATA_CACHE_CONFIG = _redis_cache("superset_explore_", 3600)

# =============================================================================
# CELERY
# =============================================================================

class CeleryConfig:
    broker_url = _redis_broker_url
    result_backend = _redis_results_url
    imports = (
        "superset.sql_lab",
        "superset.tasks.scheduler",
        "superset.tasks.thumbnails",
        "superset.tasks.cache",
    )
    task_annotations = {
        "sql_lab.get_sql_results": {"rate_limit": "100/s"},
    }
    # Hard + soft time limits prevent a runaway SQL Lab query from holding a
    # Celery slot forever. Soft limit raises SoftTimeLimitExceeded so Superset
    # can surface a clean error before the worker is SIGKILL'd at the hard limit.
    task_time_limit = 600
    task_soft_time_limit = 540
    beat_schedule = {
        "reports.scheduler": {
            "task": "reports.scheduler",
            # Superset's report dispatcher must tick every minute to honor
            # user-configured cron schedules. `expires` drops stale ticks so
            # a worker backlog can't fan out duplicate alerts after it drains.
            "schedule": crontab(minute="*"),
            "options": {"expires": 30},
        },
        "reports.prune_log": {
            "task": "reports.prune_log",
            "schedule": crontab(minute=0, hour=0),
        },
        "cache-warmup-hourly": {
            "task": "cache-warmup",
            "schedule": crontab(minute=0, hour="*"),
            "kwargs": {"strategy_name": "top_n_dashboards", "top_n": 10},
        },
    }
    worker_prefetch_multiplier = 1
    task_acks_late = True


CELERY_CONFIG = CeleryConfig  # class, not instance; Superset instantiates it

# =============================================================================
# SQL LAB
# =============================================================================

# Separate cache for async SQL Lab result payloads. Without this, workers can
# execute queries but the web container can't retrieve the results for the UI.
# Points at Redis DB 4 (same as Celery result_backend — Superset is happy sharing
# the DB as long as the key prefixes diverge).
RESULTS_BACKEND = RedisCache(
    host=_redis_host,
    port=int(_redis_port),
    password=_redis_pass_raw or None,
    db=int(_redis_results_db),
    key_prefix="superset_results_",
    default_timeout=86400,
)

SQLLAB_ASYNC_TIME_LIMIT_SEC = 600
SQLLAB_TIMEOUT = 30

# Disallow registering read-write data sources via UI without explicit override.
# Prevents a misconfigured connection from exposing DML through SQL Lab.
PREVENT_UNSAFE_DB_CONNECTIONS = True

FEATURE_FLAGS = {
    "ALERT_REPORTS": True,
    "THUMBNAILS": True,
    "THUMBNAILS_SQLA_LISTENERS": True,  # must track THUMBNAILS
    "DASHBOARD_RBAC": True,
    "ENABLE_TEMPLATE_PROCESSING": True,
    # Celery SQL Lab (this config) is sufficient; GLOBAL_ASYNC_QUERIES adds a
    # websocket layer we don't need yet.
    "GLOBAL_ASYNC_QUERIES": False,
}

# =============================================================================
# THUMBNAILS / PROXY / URL-GENERATION
# =============================================================================

# Internal URL used by the worker to render thumbnails — reaches web over the
# superset-internal Docker network, not through Traefik.
WEBDRIVER_BASEURL = os.environ.get("SUPERSET_WEBDRIVER_BASEURL", "http://superset-web:8088/")
WEBDRIVER_BASEURL_USER_FRIENDLY = os.environ["SUPERSET_DOMAIN_URL"]

# Trust X-Forwarded-Proto from Traefik so Flask sees HTTPS and url_for() returns
# https:// URLs in emailed report links. Without this, Talisman force_https + a
# plain-HTTP Traefik→container hop causes redirect loops and http:// emails.
ENABLE_PROXY_FIX = True
PROXY_FIX_CONFIG = {
    "x_for": 1,
    "x_proto": 1,
    "x_host": 1,
    "x_port": 1,
    "x_prefix": 1,
}

# =============================================================================
# AUTHENTICATION
# =============================================================================

# Local DB auth for this iteration. Authentik SSO is a planned follow-up;
# switching requires changing AUTH_TYPE, adding OAUTH_PROVIDERS, and wiring
# the Authentik OAuth2 client credentials here.
AUTH_TYPE = AUTH_DB
AUTH_USER_REGISTRATION = False

# =============================================================================
# SECURITY HEADERS
# =============================================================================

# Talisman is enabled with Superset's upstream CSP defaults (hardened
# default-src / object-src / nonce-in-script-src). Do not override CSP here
# unless adding a trusted external source — disabling it strips the
# defense-in-depth layer against stored XSS in dashboards.
TALISMAN_ENABLED = True
TALISMAN_CONFIG = {
    "force_https": True,
    "strict_transport_security": True,
    "session_cookie_secure": True,
}

# =============================================================================
# MISC
# =============================================================================

ROW_LIMIT = 5000  # Superset default — per-query soft cap in the UI
SUPERSET_WEBSERVER_TIMEOUT = 60  # long work should be async via Celery; sync cap
