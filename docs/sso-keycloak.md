# SSO com Keycloak

Este repo usa Keycloak como provedor OIDC open source para o Temporal Web UI.

## Realm importado

A imagem em `sso-keycloak` importa um realm chamado `temporal` com um client confidencial:

- Client ID: valor de `TEMPORAL_AUTH_CLIENT_ID` (`temporal-ui` por padrao)
- Redirect URI: `${TEMPORAL_UI_PUBLIC_URL}/auth/sso/callback`
- Web Origin: `${TEMPORAL_UI_PUBLIC_URL}`

O secret do client vem de `TEMPORAL_AUTH_CLIENT_SECRET`, que tambem e usado pelo Temporal UI.

No primeiro boot, o realm e importado a partir do template da imagem. Em deploys posteriores, `infra/scripts/deploy.sh` executa o reconciliador do Keycloak dentro do pod para atualizar client, secret, redirect URI, web origin, roles e usuario inicial sem depender de recriar o banco do Keycloak.

O realm tambem cria um usuario inicial com role `temporal-admin`, configurado por:

- `TEMPORAL_INITIAL_ADMIN_USERNAME`
- `TEMPORAL_INITIAL_ADMIN_EMAIL`
- `TEMPORAL_INITIAL_ADMIN_PASSWORD`

## URLs usadas pelo Temporal UI

Para Keycloak em `https://keycloak.example.com`, use:

```text
TEMPORAL_AUTH_PROVIDER_URL=https://keycloak.example.com/realms/temporal
TEMPORAL_AUTH_ISSUER_URL=https://keycloak.example.com/realms/temporal
TEMPORAL_AUTH_CLIENT_ID=temporal-ui
TEMPORAL_AUTH_CLIENT_SECRET=<mesmo secret do Keycloak>
TEMPORAL_AUTH_CALLBACK_URL=https://temporal.example.com/auth/sso/callback
```

## Usuarios

Use o usuario inicial somente para bootstrap. Depois entre no admin console do Keycloak e conecte seu provedor corporativo, ou crie usuarios/grupos adicionais no realm `temporal`.

## Nota sobre autorizacao

O Temporal UI valida a identidade do usuario pelo OIDC. Regras finas por namespace/acao exigem uma camada adicional de autorizacao no Temporal Server ou no proxy de entrada.
