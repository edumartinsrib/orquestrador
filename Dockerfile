ARG TEMPORAL_VERSION=1.31.0
ARG TEMPORAL_UI_VERSION=2.49.1

FROM temporalio/admin-tools:${TEMPORAL_VERSION} AS temporal-tools
FROM temporalio/ui:${TEMPORAL_UI_VERSION} AS temporal-ui
FROM temporalio/server:${TEMPORAL_VERSION}

USER root

RUN apk add --no-cache bash ca-certificates curl python3 \
  && update-ca-certificates

COPY --from=temporal-tools /usr/local/bin/temporal /usr/local/bin/temporal
COPY --from=temporal-tools /usr/local/bin/temporal-sql-tool /usr/local/bin/temporal-sql-tool
COPY --from=temporal-tools /etc/temporal/schema /etc/temporal/schema
COPY --from=temporal-ui --chown=temporal:temporal /home/ui-server /home/ui-server
COPY --chown=temporal:temporal devconsole /opt/devconsole

RUN chmod +x \
    /opt/devconsole/start.sh \
    /opt/devconsole/healthcheck.sh \
    /opt/devconsole/parse_database_url.py

USER temporal

ENV DB=postgres12 \
    BIND_ON_IP=0.0.0.0 \
    TEMPORAL_ADDRESS=127.0.0.1:7233 \
    TEMPORAL_UI_PORT=8080 \
    TEMPORAL_UI_ENABLED=true \
    TEMPORAL_CLOUD_UI=false \
    TEMPORAL_DEFAULT_NAMESPACE=default \
    TEMPORAL_NAMESPACE=default \
    DYNAMIC_CONFIG_FILE_PATH=/opt/devconsole/dynamicconfig/docker.yaml

EXPOSE 8080 7233

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
  CMD ["/opt/devconsole/healthcheck.sh"]

ENTRYPOINT ["/opt/devconsole/start.sh"]
