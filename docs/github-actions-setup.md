# Configurar GitHub Actions

Depois de preencher `.env` e rodar o bootstrap AWS, configure as repository variables e secrets automaticamente com:

```bash
set -a
source .env
set +a

./infra/scripts/validate-deploy-env.sh
./infra/scripts/configure-github-actions.sh --dry-run
./infra/scripts/configure-github-actions.sh
```

O script usa `GITHUB_REPOSITORY=owner/repo` para saber qual repositorio configurar.

## O que o script envia como variable

- Dados AWS/EKS.
- Chave `ENABLE_AWS_DEPLOY`, que habilita deploy automatico em push quando definida como `true`.
- Versoes pinadas do Helm Chart do Temporal e das imagens Temporal.
- Hostnames publicos.
- Configuracao OIDC do Temporal UI.
- Usuario inicial do realm Keycloak `temporal`, ECR e namespace SSO quando `DEPLOY_KEYCLOAK=true`.

## O que o script envia como secret

- `TEMPORAL_DB_PASSWORD`
- `TEMPORAL_AUTH_CLIENT_SECRET`

Se `DEPLOY_KEYCLOAK=true`, tambem envia:

- `TEMPORAL_INITIAL_ADMIN_PASSWORD`
- `KEYCLOAK_DB_PASSWORD`
- `KEYCLOAK_ADMIN_PASSWORD`

O script recusa valores de exemplo como `replace-me`, `example.com`, `owner/repo` e `123456789012`.

Mantenha `ENABLE_AWS_DEPLOY=false` durante testes locais. Depois do primeiro deploy manual validado, altere a repository variable para `true` se quiser que pushes em `main` disparem deploy automaticamente.

## Requisitos

- GitHub CLI autenticado: `gh auth status`
- Permissao para administrar variables/secrets no repositorio
- `.env` preenchido com valores reais
