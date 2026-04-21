import os
from celery.schedules import crontab

# =============================================================================
# SECURITY
# =============================================================================

SECRET_KEY = os.environ.get("SUPERSET_SECRET_KEY")
if not SECRET_KEY:
    raise RuntimeError(
        "SUPERSET_SECRET_KEY is not set. "
        "Generate with: openssl rand -base64 42"
    )

# =============================================================================
# METADATA DATABASE
# =============================================================================

_db_user = os.environ["SUPERSET_DB_USER"]
_db_pass = os.environ["SUPERSET_DB_PASSWORD"]
_db_host = os.environ.get("SUPERSET_DB_HOST", "specus-production-database-rkpsij")
_db_port = os.environ.get("SUPERSET_DB_PORT", "5432")
_db_name = os.environ.get("SUPERSET_DB_NAME", "superset")

SQLALCHEMY_DATABASE_URI = (
    f"postgresql+psycopg2://{_db_user}:{_db_pass}@{_db_host}:{_db_port}/{_db_name}"
)

SQLALCHEMY_POOL_SIZE = 5
SQLALCHEMY_MAX_OVERFLOW = 5
SQLALCHEMY_POOL_TIMEOUT = 30
SQLALCHEMY_POOL_RECYCLE = 3600

# =============================================================================
# REDIS (cache DB 2, broker DB 3, results DB 4)
# =============================================================================

_redis_host = os.environ.get("REDIS_HOST", "specus-production-redis-h08jhy")
_redis_port = os.environ.get("REDIS_PORT", "6379")
_redis_pass = os.environ.get("REDIS_PASSWORD", "")
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

CACHE_CONFIG = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_DEFAULT_TIMEOUT": 300,
    "CACHE_KEY_PREFIX": "superset_",
    "CACHE_REDIS_URL": _redis_cache_url,
}

DATA_CACHE_CONFIG = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_DEFAULT_TIMEOUT": 3600,
    "CACHE_KEY_PREFIX": "superset_data_",
    "CACHE_REDIS_URL": _redis_cache_url,
}

FILTER_STATE_CACHE_CONFIG = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_DEFAULT_TIMEOUT": 3600,
    "CACHE_KEY_PREFIX": "superset_filter_",
    "CACHE_REDIS_URL": _redis_cache_url,
}

EXPLORE_FORM_DATA_CACHE_CONFIG = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_DEFAULT_TIMEOUT": 3600,
    "CACHE_KEY_PREFIX": "superset_explore_",
    "CACHE_REDIS_URL": _redis_cache_url,
}

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
    beat_schedule = {
        "reports.scheduler": {
            "task": "reports.scheduler",
            "schedule": crontab(minute="*", hour="*"),
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


CELERY_CONFIG = CeleryConfig

# =============================================================================
# ASYNC QUERY / SQL LAB
# =============================================================================

RESULTS_BACKEND = None  # Uses Celery result_backend (Redis DB 4) — do not override

FEATURE_FLAGS = {
    "ALERT_REPORTS": True,
    "THUMBNAILS": True,
    "THUMBNAILS_SQLA_LISTENERS": True,
    "DASHBOARD_RBAC": True,
    "ENABLE_TEMPLATE_PROCESSING": True,
    "GLOBAL_ASYNC_QUERIES": False,  # Uses Celery SQL Lab instead
}

# =============================================================================
# THUMBNAILS / SCREENSHOTS
# =============================================================================

# Internal URL used by the worker to render thumbnails — reaches web over the
# superset-internal Docker network, not through Traefik.
WEBDRIVER_BASEURL = os.environ.get("SUPERSET_WEBDRIVER_BASEURL", "http://superset-web:8088/")
WEBDRIVER_BASEURL_USER_FRIENDLY = os.environ.get(
    "SUPERSET_DOMAIN_URL", "https://bi.specus.biz/"
)

# =============================================================================
# AUTHENTICATION
# =============================================================================

# Local DB auth for this iteration.
# Authentik OAuth2 SSO: see follow-up plan (feat/superset-authentik-sso)
from flask_appbuilder.security.manager import AUTH_DB  # noqa: E402

AUTH_TYPE = AUTH_DB
AUTH_USER_REGISTRATION = False

# =============================================================================
# SECURITY HEADERS
# =============================================================================

TALISMAN_ENABLED = True
TALISMAN_CONFIG = {
    "force_https": True,
    "strict_transport_security": True,
    "session_cookie_secure": True,
    "content_security_policy": False,  # Superset's CSP is managed via FAB
}

# =============================================================================
# MISC
# =============================================================================

ROW_LIMIT = 5000
SUPERSET_WEBSERVER_TIMEOUT = 300
SUPERSET_WEBSERVER_ADDRESS = "0.0.0.0"
