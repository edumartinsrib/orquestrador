# Orquestrador Temporal OSS

Projeto base para rodar Temporal em modo self-hosted/open source no Kubernetes da AWS (EKS), com SSO OIDC usando Keycloak, CI/CD por GitHub Actions, imagem customizada do Keycloak em ECR e worker Python pronto para rodar em maquina local.

## O que este repo entrega

- `infra/temporal`: valores Helm para instalar Temporal OSS no EKS usando PostgreSQL externo.
- `sso-keycloak`: imagem Keycloak com import de realm OIDC para autenticar o Temporal UI.
- `infra/k8s`: manifests Kubernetes renderizados por variaveis de ambiente.
- `worker`: worker Temporal Python para maquina local, com tutorial de instalacao no Windows.
- `.github/workflows/deploy.yml`: pipeline manual para build, push no ECR e deploy no EKS.
- `.github/workflows/validate.yml`: validacao sem deploy para pull requests e push em `main`.

## Arquitetura

```text
GitHub Actions
  -> assume role AWS via OIDC
  -> build Keycloak
  -> push ECR
  -> kubectl/helm no EKS

EKS
  temporal namespace
    - Temporal frontend/history/matching e system worker interno via Helm
    - Temporal UI com OIDC habilitado
  temporal-sso namespace
    - Keycloak OSS como IdP OIDC

Maquina local/Windows
  - worker Python conectado ao Temporal frontend por rede privada, VPN/Tailscale ou port-forward administrativo

RDS PostgreSQL
  - temporal
  - temporal_visibility
  - keycloak, somente se DEPLOY_KEYCLOAK=true
```

## Pre-requisitos na AWS

1. Um cluster EKS existente.
2. AWS Load Balancer Controller instalado no cluster.
3. Certificado ACM para `TEMPORAL_UI_HOST` e, se `DEPLOY_KEYCLOAK=true`, para `KEYCLOAK_PUBLIC_HOSTNAME`.
4. PostgreSQL externo, preferencialmente RDS, com os bancos:
   - `temporal`
   - `temporal_visibility`
   - `keycloak`, somente se `DEPLOY_KEYCLOAK=true`
5. Role IAM para GitHub Actions com permissao para ECR, EKS e STS OIDC.
6. Se `DEPLOY_KEYCLOAK=true`, repositorio ECR para a imagem customizada do Keycloak, ou permissao para a pipeline cria-lo.

## Deploy manual

Se ainda nao criou ECR/IAM para o CI, rode primeiro o bootstrap:

```bash
cp .env.example .env
$EDITOR .env
set -a
source .env
set +a

./infra/scripts/bootstrap-aws.sh --dry-run
./infra/scripts/bootstrap-aws.sh
```

Atalho equivalente para o dry-run do bootstrap:

```bash
make aws-preflight
```

Depois copie o `AWS_ROLE_TO_ASSUME` exibido pelo script para `.env` e valide o conjunto completo:

```bash
make deploy-preflight
```

Tambem copie o `AWS_ROLE_TO_ASSUME` para as repository variables do GitHub.

Para configurar o GitHub Actions a partir do `.env`:

```bash
./infra/scripts/configure-github-actions.sh --dry-run
./infra/scripts/configure-github-actions.sh
```

Para instalar ou atualizar no EKS:

```bash
cp .env.example .env
$EDITOR .env
set -a
source .env
set +a

aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME"

./infra/scripts/deploy.sh
```

Quando `DEPLOY_KEYCLOAK=true`, `deploy.sh` deriva `KEYCLOAK_IMAGE` a partir de `AWS_ACCOUNT_ID`, `AWS_REGION`, `ECR_KEYCLOAK_REPOSITORY` e `IMAGE_TAG` se a variavel nao estiver definida. Quando `DEPLOY_KEYCLOAK=false`, nenhum recurso de Keycloak/ECR e aplicado.

Detalhes do bootstrap AWS ficam em [infra/aws/README.md](infra/aws/README.md).
Detalhes da configuracao do GitHub Actions ficam em [docs/github-actions-setup.md](docs/github-actions-setup.md).
O passo a passo operacional completo fica em [docs/deploy-runbook.md](docs/deploy-runbook.md).

## Deploy por CI/CD

Configure estes repository variables no GitHub:

- `AWS_REGION`
- `AWS_ACCOUNT_ID`
- `AWS_ROLE_TO_ASSUME`
- `EKS_CLUSTER_NAME`
- `TEMPORAL_HELM_CHART_VERSION`
- `TEMPORAL_SERVER_IMAGE_TAG`
- `TEMPORAL_ADMINTOOLS_IMAGE_TAG`
- `TEMPORAL_UI_IMAGE_TAG`
- `TEMPORAL_NAMESPACE`
- `TEMPORAL_DB_HOST`
- `TEMPORAL_DB_PORT`
- `TEMPORAL_DB_NAME`
- `TEMPORAL_VISIBILITY_DB_NAME`
- `TEMPORAL_DB_USER`
- `TEMPORAL_UI_HOST`
- `TEMPORAL_UI_PUBLIC_URL`
- `TEMPORAL_AUTH_PROVIDER_URL`
- `TEMPORAL_AUTH_ISSUER_URL`
- `TEMPORAL_AUTH_CLIENT_ID`
- `DEPLOY_KEYCLOAK`
- `ALB_CERTIFICATE_ARN`
- `ALB_SCHEME`

Configure tambem estes repository variables se `DEPLOY_KEYCLOAK=true`:

- `ECR_KEYCLOAK_REPOSITORY`
- `KEYCLOAK_IMAGE_TAG`
- `SSO_NAMESPACE`
- `TEMPORAL_INITIAL_ADMIN_USERNAME`
- `TEMPORAL_INITIAL_ADMIN_EMAIL`
- `KEYCLOAK_PUBLIC_HOSTNAME`
- `KEYCLOAK_PUBLIC_URL`
- `KEYCLOAK_DB_HOST`
- `KEYCLOAK_DB_PORT`
- `KEYCLOAK_DB_NAME`
- `KEYCLOAK_DB_USER`
- `KEYCLOAK_ADMIN_USERNAME`

Configure estes repository secrets:

- `TEMPORAL_DB_PASSWORD`
- `TEMPORAL_AUTH_CLIENT_SECRET`

Configure tambem estes repository secrets se `DEPLOY_KEYCLOAK=true`:

- `TEMPORAL_INITIAL_ADMIN_PASSWORD`
- `KEYCLOAK_DB_PASSWORD`
- `KEYCLOAK_ADMIN_PASSWORD`

Quando executada manualmente, a workflow `.github/workflows/deploy.yml`:

1. assume a role AWS por OIDC;
2. cria o repositorio ECR do Keycloak se `DEPLOY_KEYCLOAK=true`;
3. builda e publica a imagem `sso-keycloak` se `DEPLOY_KEYCLOAK=true`;
4. atualiza o kubeconfig para o EKS;
5. executa `infra/scripts/deploy.sh`.

Por enquanto, push em `main` roda apenas validacao. O deploy para AWS/EKS fica manual por `workflow_dispatch`.

## Validacao local

Antes de publicar, rode:

```bash
make validate-full
```

Ou, diretamente:

```bash
./infra/scripts/validate-local.sh
./infra/scripts/validate-extended-local.sh
```

O primeiro script valida o worker Python, renderizacao dos templates, JSON/YAML e build da imagem Docker do Keycloak quando Docker estiver disponivel. O segundo renderiza o chart Helm oficial do Temporal via Docker, roda actionlint nos workflows e verifica que variaveis sensiveis em Deployments usam Kubernetes Secrets.

Para testar o stack inteiro sem AWS:

```bash
make local-full
```

Ou, diretamente:

```bash
./local/scripts/local-up.sh
./local/scripts/local-test.sh
./local/scripts/local-sso-browser-test.sh
```

Temporal UI local: http://localhost:8080. Login SSO local: `temporal.admin` / `temporal-admin`. O teste de workflow inicia um worker Python como processo local temporario, conectado em `localhost:7233`.

Detalhes em [local/README.md](local/README.md).

Depois de um deploy, rode:

```bash
./infra/scripts/smoke-test.sh
```

Esse script verifica rollouts no Kubernetes e, por padrao, os endpoints publicos do Temporal UI e do OIDC.

## Seguranca importante

O SSO OIDC deste projeto protege o Temporal Web UI. O endpoint gRPC do Temporal (`:7233`) deve continuar privado dentro da VPC/cluster, ou ser exposto somente com mTLS, VPN, Tailscale, PrivateLink ou uma camada de autorizacao propria. Workers locais no Windows devem preferir VPN/Tailscale ou `kubectl port-forward` para operacao administrativa.

## Referencias oficiais usadas

- Temporal self-hosted security: https://docs.temporal.io/self-hosted-guide/security
- Temporal Helm charts: https://github.com/temporalio/helm-charts
- Temporal Web UI env vars: https://docs.temporal.io/references/web-ui-environment-variables
- Temporal Python SDK: https://docs.temporal.io/develop/python
- Keycloak container docs: https://www.keycloak.org/server/containers
