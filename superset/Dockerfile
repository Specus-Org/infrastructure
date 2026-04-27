ARG SUPERSET_VERSION=4.1.2
FROM apache/superset:${SUPERSET_VERSION}

USER root
# Install PostgreSQL driver required for the metadata DB and SQL Lab connections.
# The base apache/superset image ships without database drivers by design.
RUN pip install --no-cache-dir psycopg2-binary==2.9.9
USER superset
