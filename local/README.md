# Teste local sem AWS

Este modo sobe tudo localmente com Docker Compose:

- PostgreSQL do Temporal
- Temporal Server OSS
- Temporal UI com OIDC
- Keycloak OSS
- PostgreSQL do Keycloak

O worker de negocio roda fora do Compose como processo Python local durante o teste.

## Subir

```bash
./local/scripts/local-up.sh
```

URLs:

- Temporal UI: http://localhost:8080
- Keycloak: http://keycloak.localhost:8081
- Temporal gRPC: localhost:7233

Login Keycloak admin:

- usuario: `admin`
- senha: `admin`

Login SSO no Temporal UI:

- usuario: `temporal.admin`
- senha: `temporal-admin`

## Testar workflow

```bash
./local/scripts/local-test.sh
```

O teste cria `.venv` em `worker/`, instala `requirements.txt`, inicia o worker Python local temporariamente e dispara `GreetingWorkflow` na task queue `default-task-queue`.

Para testar o login SSO real no navegador headless:

```bash
./local/scripts/local-sso-browser-test.sh
```

## Derrubar

```bash
./local/scripts/local-down.sh
```

Para apagar volumes:

```bash
./local/scripts/local-down.sh --volumes
```

## Observacao sobre SSO local

O Keycloak local usa `http://keycloak.localhost:8081/realms/temporal` como issuer. O hostname `keycloak.localhost` resolve para loopback no navegador e e mapeado para `host-gateway` dentro do container do Temporal UI, permitindo que o callback OIDC troque o code por tokens usando o mesmo issuer.
