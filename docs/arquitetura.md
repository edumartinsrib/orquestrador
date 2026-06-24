# Arquitetura de referencia

## Decisoes principais

1. Temporal roda pelo Helm Chart oficial `temporalio/helm-charts`.
2. O banco nao roda dentro do chart. Use PostgreSQL externo, como RDS, para `temporal` e `temporal_visibility`.
3. SSO fica no Temporal UI via OIDC. O provedor de identidade padrao deste repo e Keycloak OSS.
4. Workers rodam separados do servidor Temporal, fora do Kubernetes. O scaffold inclui um worker Python para maquina local/Windows.
5. A API gRPC do Temporal nao deve ser publicada diretamente na internet sem controles adicionais.

## Fluxo de autenticacao

```text
Usuario -> ALB HTTPS -> Temporal UI -> Keycloak OIDC -> Temporal UI session
Temporal UI -> Temporal frontend gRPC interno -> Temporal Server
Worker Python local -> rede privada/VPN/Tailscale/port-forward -> Temporal frontend gRPC -> Task Queue
```

## Limite do SSO no Temporal OSS

O OIDC nativo do Temporal Web UI autentica usuarios no UI. Ele nao substitui, sozinho, uma politica completa de autorizacao para todos os SDK clients. Para isso, adicione uma destas camadas:

- manter o frontend gRPC privado na VPC;
- mTLS entre clients/workers e Temporal frontend;
- autorizacao JWT no Temporal Server com `server.config.authorization`;
- proxy/API gateway proprio validando tokens antes de encaminhar gRPC.

Este scaffold deixa o caminho seguro padrao: UI publico com SSO, gRPC privado.
