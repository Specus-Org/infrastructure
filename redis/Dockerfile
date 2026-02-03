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

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD redis-cli -a "${REDIS_PASSWORD:-}" ping 2>/dev/null | grep -q PONG || exit 1

# Expose Redis port
EXPOSE 6379

# Run Redis with custom config
CMD ["redis-server", "/usr/local/etc/redis/redis.conf"]
