ARG KEYCLOAK_IMAGE_TAG=26.6.3

FROM quay.io/keycloak/keycloak:${KEYCLOAK_IMAGE_TAG} AS builder
ENV KC_DB=postgres
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true
RUN /opt/keycloak/bin/kc.sh build

FROM quay.io/keycloak/keycloak:${KEYCLOAK_IMAGE_TAG}
COPY --from=builder /opt/keycloak/ /opt/keycloak/
COPY realm-template.json /opt/keycloak/templates/realm-template.json
COPY entrypoint.sh /opt/keycloak/bin/render-realm-and-start.sh
COPY reconcile-temporal-realm.sh /opt/keycloak/bin/reconcile-temporal-realm.sh
USER root
RUN mkdir -p /opt/keycloak/data/import \
  && chown -R 1000:0 /opt/keycloak/data/import /opt/keycloak/templates /opt/keycloak/bin/render-realm-and-start.sh /opt/keycloak/bin/reconcile-temporal-realm.sh \
  && chmod 0775 /opt/keycloak/data/import \
  && chmod 0755 /opt/keycloak/bin/render-realm-and-start.sh /opt/keycloak/bin/reconcile-temporal-realm.sh
USER 1000

ENTRYPOINT ["/opt/keycloak/bin/render-realm-and-start.sh"]
CMD ["start", "--optimized", "--import-realm"]
