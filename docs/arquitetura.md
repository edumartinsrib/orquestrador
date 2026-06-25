# Arquitetura de referencia

## Decisoes principais

1. O runtime principal roda na DevConsole por meio do `Dockerfile` da raiz.
2. O container principal inicia Temporal Server e Temporal UI no mesmo ambiente.
3. O banco nao roda dentro do container. Use PostgreSQL externo, como RDS, para `temporal` e `temporal_visibility`.
4. A conexao do banco entra por `DATABASE_URL`/`TEMPORAL_DATABASE_URL` ou pelas variaveis `TEMPORAL_DB_*`.
5. SSO fica no Temporal UI via OIDC. Keycloak permanece disponivel como IdP opcional/legado.
6. Workers rodam separados do servidor Temporal, fora da DevConsole. O scaffold inclui um worker Python para maquina local/Windows.
7. A API gRPC do Temporal nao deve ser publicada diretamente na internet sem controles adicionais.

## Fluxo de autenticacao

```text
Usuario -> DevConsole HTTPS -> Temporal UI -> OIDC opcional -> Temporal UI session
Temporal UI -> Temporal frontend gRPC local no container -> Temporal Server
Worker Python externo -> rede privada/VPN/Tailscale/PrivateLink -> Temporal frontend gRPC -> Task Queue
```

## Limite do SSO no Temporal OSS

O OIDC nativo do Temporal Web UI autentica usuarios no UI. Ele nao substitui, sozinho, uma politica completa de autorizacao para todos os SDK clients. Para isso, adicione uma destas camadas:

- manter o frontend gRPC privado na VPC;
- mTLS entre clients/workers e Temporal frontend;
- autorizacao JWT no Temporal Server com `server.config.authorization`;
- proxy/API gateway proprio validando tokens antes de encaminhar gRPC.

Este scaffold deixa o caminho seguro padrao: UI publico com SSO, gRPC privado.
