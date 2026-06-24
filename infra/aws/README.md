# Bootstrap AWS para o CI/CD

Esta pasta contem um bootstrap minimo para deixar o GitHub Actions apto a publicar imagens no ECR, quando Keycloak for gerenciado por este repo, e chamar deploy no EKS.

## O que o bootstrap cria

- Repositorio ECR do Keycloak, somente quando `DEPLOY_KEYCLOAK=true`.
- IAM OIDC provider `token.actions.githubusercontent.com`, se ainda nao existir.
- IAM role para GitHub Actions.
- IAM policy anexada a role com permissoes de ECR e `eks:DescribeCluster`.

O acesso Kubernetes ao cluster EKS e configurado separadamente via `aws eks create-access-entry`/`associate-access-policy`, porque isso depende do modelo de acesso do seu cluster.

## Como executar

```bash
export AWS_REGION=us-east-1
export EKS_CLUSTER_NAME=my-eks-cluster
export GITHUB_REPOSITORY=owner/repo
export GITHUB_REF_PATTERN=ref:refs/heads/main
export DEPLOY_KEYCLOAK=true
export ECR_KEYCLOAK_REPOSITORY=temporal-keycloak
export AWS_ROLE_NAME=github-actions-temporal-deploy

./infra/scripts/bootstrap-aws.sh --dry-run
./infra/scripts/bootstrap-aws.sh
```

No final, copie o ARN exibido para a GitHub repository variable `AWS_ROLE_TO_ASSUME`.

Se voce usar SSO externo e `DEPLOY_KEYCLOAK=false`, o bootstrap nao exige nem cria repositorio ECR.

## Associar a role ao EKS

O bootstrap imprime comandos como estes:

```bash
aws eks create-access-entry \
  --cluster-name "$EKS_CLUSTER_NAME" \
  --principal-arn "$ROLE_ARN" \
  --type STANDARD

aws eks associate-access-policy \
  --cluster-name "$EKS_CLUSTER_NAME" \
  --principal-arn "$ROLE_ARN" \
  --access-scope type=cluster \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy
```

Para producao, reduza a permissao Kubernetes depois do primeiro deploy. O deploy precisa criar/atualizar namespaces, secrets, deployments, services, ingresses e Helm releases.
