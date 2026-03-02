#!/bin/sh
# =============================================================================
# Specus Redis Entrypoint
# =============================================================================
# Conditionally passes --requirepass when REDIS_PASSWORD is set.
# Requires ALLOW_EMPTY_PASSWORD=true to start without authentication.
# =============================================================================

set -e

if [ -n "$REDIS_PASSWORD" ]; then
    exec redis-server /usr/local/etc/redis/redis.conf --requirepass "$REDIS_PASSWORD"
elif [ "$ALLOW_EMPTY_PASSWORD" = "true" ]; then
    echo "WARNING: Starting Redis without authentication (ALLOW_EMPTY_PASSWORD=true)"
    exec redis-server /usr/local/etc/redis/redis.conf
else
    echo "FATAL: REDIS_PASSWORD is not set. Set ALLOW_EMPTY_PASSWORD=true to override."
    exit 1
fi
