# Deploy na DevConsole

Este e o caminho principal de runtime do projeto. A DevConsole deve construir o
`Dockerfile` da raiz e iniciar a imagem resultante; o container prepara o
schema do Temporal, sobe o Temporal Server, cria o namespace padrao e inicia o
Temporal UI no mesmo ambiente.

O worker de negocio continua fora deste ambiente. Configure o worker para
apontar para o endpoint gRPC privado exposto pela DevConsole.

## Variaveis principais

Configure no ambiente principal da DevConsole:

- `DATABASE_URL`: URL PostgreSQL do store principal, no formato
  `postgresql://usuario:senha@host:5432/temporal`.
- `TEMPORAL_VISIBILITY_DATABASE_URL`: opcional. Se omitida, o container usa o
  mesmo host, porta, usuario e senha de `DATABASE_URL`, com o banco definido por
  `TEMPORAL_VISIBILITY_DB_NAME` ou `temporal_visibility`.
- `TEMPORAL_UI_PUBLIC_URL`: URL publica do Temporal UI, usada para callback SSO.
- `TEMPORAL_AUTH_ENABLED`: `true` para habilitar OIDC no UI; padrao `false`.
- `TEMPORAL_AUTH_PROVIDER_URL`, `TEMPORAL_AUTH_ISSUER_URL`,
  `TEMPORAL_AUTH_CLIENT_ID`, `TEMPORAL_AUTH_CLIENT_SECRET`: obrigatorias quando
  `TEMPORAL_AUTH_ENABLED=true`.
- `TEMPORAL_NAMESPACE` ou `TEMPORAL_DEFAULT_NAMESPACE`: namespace criado no
  bootstrap; padrao `default`.
- `TEMPORAL_UI_PORT`: porta HTTP do UI; padrao `8080`. Se a DevConsole injetar
  `PORT`, ele sera usado quando `TEMPORAL_UI_PORT` nao estiver definido.

Para RDS com TLS, use `sslmode=require` na URL:

```text
DATABASE_URL=postgresql://temporal:senha@meu-rds:5432/temporal?sslmode=require
```

Se preferir variaveis separadas, o container tambem aceita
`TEMPORAL_DB_HOST`, `TEMPORAL_DB_PORT`, `TEMPORAL_DB_NAME`,
`TEMPORAL_DB_USER`, `TEMPORAL_DB_PASSWORD` e `TEMPORAL_DB_TLS_ENABLED=true`.

## Banco de dados

O Temporal usa dois bancos PostgreSQL:

- `temporal`
- `temporal_visibility`

O usuario da aplicacao pode ter permissao para criar esses bancos. Se eles ja
forem provisionados pela plataforma, o bootstrap ignora a criacao e aplica
apenas o schema. Para ambientes onde o schema e gerenciado externamente, defina
`TEMPORAL_SKIP_SCHEMA_SETUP=true`.

## Portas

- `8080`: Temporal UI, HTTP principal para a DevConsole.
- `7233`: Temporal frontend gRPC. Mantenha privado e use apenas pela rede
  interna/VPN/Tailscale/PrivateLink para workers e clientes SDK.

## Teste local da imagem

```bash
make devconsole-build
```

Exemplo com PostgreSQL local em Docker:

```bash
docker network create temporal-devconsole
docker run -d --name temporal-devconsole-postgres --network temporal-devconsole \
  -e POSTGRES_USER=temporal \
  -e POSTGRES_PASSWORD=temporal \
  postgres:16

docker run --rm --network temporal-devconsole \
  -p 8080:8080 -p 7233:7233 \
  -e DATABASE_URL=postgresql://temporal:temporal@temporal-devconsole-postgres:5432/temporal \
  -e TEMPORAL_VISIBILITY_DB_NAME=temporal_visibility \
  temporal-devconsole:local
```

Depois acesse `http://localhost:8080`.
