ARG SUPERSET_VERSION=4.1.2
FROM apache/superset:${SUPERSET_VERSION}

USER root

COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY superset_config.py /app/pythonpath/superset_config.py

USER superset

ENV SUPERSET_CONFIG_PATH=/app/pythonpath/superset_config.py \
    PYTHONPATH=/app/pythonpath:$PYTHONPATH
