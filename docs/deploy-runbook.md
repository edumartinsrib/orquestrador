# Runbook de deploy

Este e o fluxo recomendado para sair de uma pasta nova ate Temporal OSS com SSO no EKS.

## 1. Preencher `.env`

```bash
cp .env.example .env
$EDITOR .env
```

Troque todos os placeholders:

- `123456789012`
- `owner/repo`
- `my-eks-cluster`
- `example.com`
- `xxxxxxxx`
- `replace-me`

## 2. Validar localmente

```bash
make validate-full
```

Ou, diretamente:

```bash
./infra/scripts/validate-local.sh
./infra/scripts/validate-extended-local.sh
```

Essas validacoes nao acessam AWS/EKS. A validacao estendida usa Docker para renderizar o Helm Chart do Temporal, validar os workflows do GitHub Actions e verificar que variaveis sensiveis em Deployments usam Kubernetes Secrets.
As versoes do chart/imagens ficam fixadas em `.env` por `TEMPORAL_HELM_CHART_VERSION`, `TEMPORAL_SERVER_IMAGE_TAG`, `TEMPORAL_ADMINTOOLS_IMAGE_TAG` e `TEMPORAL_UI_IMAGE_TAG`.

## 3. Criar role IAM do GitHub e, se aplicavel, ECR

```bash
set -a
source .env
set +a

make aws-preflight
```

Ou, diretamente:

```bash
./infra/scripts/bootstrap-aws.sh --dry-run
./infra/scripts/bootstrap-aws.sh
```

Copie o `AWS_ROLE_TO_ASSUME=...` impresso pelo script para `.env`.
Depois valide o `.env` completo sem acessar AWS/EKS/GitHub:

```bash
make deploy-preflight
```

Ou, diretamente:

```bash
./infra/scripts/validate-deploy-env.sh
```

## 4. Dar acesso da role ao EKS

Rode os dois comandos impressos pelo bootstrap:

```bash
aws eks create-access-entry ...
aws eks associate-access-policy ...
```

No primeiro deploy, `AmazonEKSClusterAdminPolicy` e o caminho direto. Depois de estabilizar, reduza a permissao para os namespaces do projeto.

## 5. Configurar GitHub Actions

```bash
./infra/scripts/configure-github-actions.sh --dry-run
./infra/scripts/configure-github-actions.sh
```

O script envia variables e secrets para o repositorio definido em `GITHUB_REPOSITORY`.

## 6. Deploy manual inicial

```bash
aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME"

./infra/scripts/deploy.sh
```

Se `DEPLOY_KEYCLOAK=true` e voce fizer deploy manual sem GitHub Actions, publique a imagem do Keycloak antes do deploy:

```bash
export KEYCLOAK_IMAGE="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_KEYCLOAK_REPOSITORY:$IMAGE_TAG"

docker build -t "$KEYCLOAK_IMAGE" ./sso-keycloak

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

docker push "$KEYCLOAK_IMAGE"
```

Se `DEPLOY_KEYCLOAK=false`, pule o ECR e a imagem do Keycloak; o deploy usa apenas o OIDC externo configurado em `TEMPORAL_AUTH_*`.

## 7. Deploy automatico

Depois do primeiro deploy, pushes em `main` disparam `.github/workflows/deploy.yml`.

## 8. Validacao em runtime

```bash
./infra/scripts/smoke-test.sh
```

O smoke test verifica:

- rollouts dos deployments Temporal;
- o `temporal-worker` interno do Temporal Helm, que nao e o worker Python de negocio;
- rollout do Keycloak quando `DEPLOY_KEYCLOAK=true`;
- `/healthz` do Temporal UI;
- discovery OIDC do issuer configurado;
- discovery OIDC do realm `temporal` no Keycloak.

Se DNS/ALB ainda estiver propagando e voce quiser validar somente Kubernetes:

```bash
SMOKE_PUBLIC_HTTP_CHECKS=false ./infra/scripts/smoke-test.sh
```

Depois dos checks, abra:

- `TEMPORAL_UI_PUBLIC_URL`
- `KEYCLOAK_PUBLIC_URL`

No Temporal UI, o botao de login deve redirecionar para Keycloak e retornar para `/auth/sso/callback`.

## 9. Rodar worker Python local

O worker nao e implantado no EKS. Depois do Temporal estar acessivel por rede privada, VPN/Tailscale ou port-forward:

```bash
cd worker
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt

export TEMPORAL_ADDRESS=localhost:7233
export TEMPORAL_NAMESPACE=default
export TEMPORAL_TASK_QUEUE=default-task-queue
.venv/bin/python -m temporal_worker.worker
```

No Windows, use [worker/README.md](../worker/README.md) para instalar como servico.
