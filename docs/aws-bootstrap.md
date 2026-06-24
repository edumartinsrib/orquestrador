# Bootstrap AWS/EKS

## 1. Banco PostgreSQL

Se `DEPLOY_KEYCLOAK=true`, crie tres bancos no PostgreSQL/RDS:

```sql
CREATE DATABASE temporal;
CREATE DATABASE temporal_visibility;
CREATE DATABASE keycloak;
```

Se `DEPLOY_KEYCLOAK=false`, o banco `keycloak` nao e necessario. Use usuarios separados se quiser isolamento fino. O scaffold aceita um usuario unico para Temporal e outro para Keycloak.

## 2. Certificados

Em ACM, emita ou importe certificados para:

- `temporal.example.com`
- `keycloak.example.com`, somente se `DEPLOY_KEYCLOAK=true`

Use o ARN em `ALB_CERTIFICATE_ARN`.

## 3. AWS Load Balancer Controller

Instale o AWS Load Balancer Controller no EKS antes de aplicar os manifests. Os Ingresses deste repo usam `ingressClassName: alb`.

## 4. GitHub OIDC na AWS

Use o script incluso para criar OIDC provider e role IAM. Ele tambem cria ECR quando `DEPLOY_KEYCLOAK=true`:

```bash
set -a
source .env
set +a
./infra/scripts/bootstrap-aws.sh --dry-run
./infra/scripts/bootstrap-aws.sh
```

O script imprime o ARN para `AWS_ROLE_TO_ASSUME` e os comandos `aws eks create-access-entry` / `associate-access-policy`.

### Permissoes criadas

O bootstrap cria uma IAM role assumida pelo GitHub Actions via `token.actions.githubusercontent.com`. A trust policy limita owner/repo/branch por `GITHUB_REPOSITORY` e `GITHUB_REF_PATTERN`. A role recebe permissoes para:

- `ecr:CreateRepository`
- `ecr:DescribeRepositories`
- `ecr:GetAuthorizationToken`
- `ecr:BatchCheckLayerAvailability`
- `ecr:InitiateLayerUpload`
- `ecr:UploadLayerPart`
- `ecr:CompleteLayerUpload`
- `ecr:PutImage`
- `eks:DescribeCluster`

Tambem associe a role ao EKS com permissao Kubernetes suficiente para criar namespaces, secrets, deployments, services, ingresses e instalar Helm releases. O bootstrap imprime comandos usando `AmazonEKSClusterAdminPolicy` para o primeiro deploy; em producao, reduza esse acesso depois de estabilizar os manifests.

## 5. Primeiro deploy

Antes do primeiro deploy, confirme:

```bash
aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME"
kubectl get nodes
kubectl get ingressclass
```

Depois rode:

```bash
./infra/scripts/deploy.sh
```
