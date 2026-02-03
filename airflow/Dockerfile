# =============================================================================
# Specus Apache Airflow Custom Image
# =============================================================================
# Based on official Airflow image with additional dependencies
# Configured for LocalExecutor (no Celery workers needed)
# =============================================================================

FROM apache/airflow:2.10.4-python3.12

LABEL org.opencontainers.image.title="Specus Airflow"
LABEL org.opencontainers.image.description="Apache Airflow with LocalExecutor and custom dependencies"
LABEL org.opencontainers.image.source="https://github.com/adryanev/specus-infrastructure"

# Switch to root to install system dependencies
USER root

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Switch back to airflow user
USER airflow

# Install Python dependencies
# Add any additional Python packages your DAGs need here
RUN pip install --no-cache-dir \
    apache-airflow-providers-postgres \
    apache-airflow-providers-redis \
    apache-airflow-providers-http \
    apache-airflow-providers-common-sql \
    requests \
    pandas \
    psycopg2-binary

# Copy custom airflow configuration
COPY --chown=airflow:root airflow.cfg /opt/airflow/airflow.cfg

# Health check for webserver
HEALTHCHECK --interval=30s --timeout=30s --start-period=60s --retries=5 \
    CMD curl --fail http://localhost:8080/health || exit 1

# Expose webserver port
EXPOSE 8080
