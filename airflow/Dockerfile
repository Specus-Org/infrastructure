# =============================================================================
# Specus Apache Airflow Custom Image
# =============================================================================
# Based on official Airflow image with additional dependencies
# Configured for LocalExecutor (no Celery workers needed)
# =============================================================================

FROM apache/airflow:3.1.7-python3.12

LABEL org.opencontainers.image.title="Specus Airflow 3"
LABEL org.opencontainers.image.description="Apache Airflow 3 with LocalExecutor and custom dependencies"
LABEL org.opencontainers.image.source="https://github.com/adryanev/specus-infrastructure"

# Switch to root to install system dependencies
USER root

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Switch back to airflow user
USER airflow

# Install Python dependencies
# Add any additional Python packages your DAGs need here
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Copy custom airflow configuration
COPY --chown=airflow:root airflow.cfg /opt/airflow/airflow.cfg

# Expose webserver port
EXPOSE 8080
