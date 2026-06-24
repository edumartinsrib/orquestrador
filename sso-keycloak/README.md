# Keycloak para SSO do Temporal UI

Esta imagem estende a imagem oficial do Keycloak e importa um realm `temporal` com o client OIDC definido por `TEMPORAL_AUTH_CLIENT_ID` (`temporal-ui` por padrao).

## Build local

```bash
docker build -t temporal-keycloak:local ./sso-keycloak
```

## Variaveis obrigatorias em runtime

- `TEMPORAL_UI_PUBLIC_URL`: URL publica do Temporal UI, exemplo `https://temporal.example.com`.
- `TEMPORAL_AUTH_CLIENT_SECRET`: secret do client OIDC. Use o mesmo valor no Temporal UI.
- `TEMPORAL_INITIAL_ADMIN_USERNAME`, `TEMPORAL_INITIAL_ADMIN_EMAIL`, `TEMPORAL_INITIAL_ADMIN_PASSWORD`: usuario inicial criado no realm `temporal`.
- `KC_DB_URL`, `KC_DB_USERNAME`, `KC_DB_PASSWORD`: conexao PostgreSQL do Keycloak.
- `KC_BOOTSTRAP_ADMIN_USERNAME`, `KC_BOOTSTRAP_ADMIN_PASSWORD`: primeiro admin.
- `KC_HOSTNAME`: hostname publico do Keycloak.

## Observacao

O realm cria roles `temporal-admin` e `temporal-viewer` para organizar usuarios, mas o Temporal UI self-hosted nao aplica RBAC fino por role sozinho. Use essas roles se voce adicionar uma camada de autorizacao propria depois.

O Deployment inicial usa 1 replica para evitar corrida no import do realm. Depois do primeiro deploy e validacao do realm, configure HA/cache do Keycloak e escale conforme sua necessidade.

## Reconciliação em deploys posteriores

O import do realm serve para bootstrap. Em deploys posteriores, `infra/scripts/deploy.sh` executa `/opt/keycloak/bin/reconcile-temporal-realm.sh` dentro do pod Keycloak para atualizar de forma idempotente:

- realm `temporal`;
- client OIDC, secret, redirect URI e web origin;
- roles `temporal-admin` e `temporal-viewer`;
- usuario inicial de bootstrap.
