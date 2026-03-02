# =============================================================================
# Specus Redis 7 Custom Image
# =============================================================================
# Alpine-based Redis image optimized for caching (no persistence)
# =============================================================================

FROM redis:7-alpine

LABEL org.opencontainers.image.title="Specus Redis 7"
LABEL org.opencontainers.image.description="Redis 7 Alpine configured for caching with LRU eviction"
LABEL org.opencontainers.image.source="https://github.com/adryanev/specus-infrastructure"

# Copy custom configuration
COPY redis.conf /usr/local/etc/redis/redis.conf

# Copy entrypoint script that wires REDIS_PASSWORD at runtime
COPY specus-redis-entrypoint.sh /usr/local/bin/specus-redis-entrypoint.sh
RUN chmod +x /usr/local/bin/specus-redis-entrypoint.sh

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD sh -c 'REDISCLI_AUTH="${REDIS_PASSWORD:-}" redis-cli ping 2>/dev/null | grep -q PONG' || exit 1

# Expose Redis port
EXPOSE 6379

# Entrypoint conditionally passes --requirepass if REDIS_PASSWORD is set
ENTRYPOINT ["specus-redis-entrypoint.sh"]
