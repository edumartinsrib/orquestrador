# Guia completo de instalacao e uso

Este guia ensina a instalar, configurar, validar e usar o Orquestrador Temporal
OSS deste repositorio. O runtime principal e a DevConsole do empregador, que
constroi o `Dockerfile` da raiz e inicia a aplicacao por `devconsole/start.sh`.
O worker Python de negocio roda fora da DevConsole.

## Visao geral

O projeto entrega:

- uma imagem principal com Temporal Server, Temporal UI, Temporal CLI e setup de
  schema PostgreSQL;
- um bootstrap de container em `devconsole/start.sh`;
- configuracao por variaveis de ambiente, principalmente `DATABASE_URL`;
- um worker Python de exemplo em `worker/`;
- um stack local para testes sem AWS em `local/`;
- um caminho legado/opcional para EKS em `infra/`.

Fluxo principal:

```text
DevConsole
  -> build do Dockerfile da raiz
  -> start.sh prepara schema, sobe Temporal Server, cria namespace e inicia UI
  -> banco externo via DATABASE_URL ou TEMPORAL_DATABASE_URL

Worker externo
  -> conecta no Temporal frontend gRPC por rede privada
  -> escuta a task queue configurada
```

## Requisitos

Para desenvolvimento local:

- Git.
- Docker Engine com Docker Compose.
- Python 3.12 ou superior.
- Make.
- Acesso a internet para baixar imagens Docker na primeira validacao.

Para DevConsole:

- permissao para construir o `Dockerfile` da raiz;
- PostgreSQL externo acessivel pela aplicacao;
- dois bancos PostgreSQL para Temporal:
  - `temporal`;
  - `temporal_visibility`;
- endpoint HTTP publico ou interno para o Temporal UI;
- endpoint gRPC privado para workers e clientes SDK.

Para worker Windows:

- Python 3.12;
- Git;
- Temporal CLI, se quiser testes locais;
- NSSM, se quiser instalar o worker como servico.

## Clonar o repositorio

```bash
git clone git@github.com:edumartinsrib/orquestrador.git
cd orquestrador
```

Valide a estrutura basica:

```bash
ls
```

Arquivos importantes:

- `Dockerfile`: runtime principal da DevConsole.
- `devconsole/start.sh`: start da aplicacao no container.
- `.env.example`: modelo de variaveis.
- `Makefile`: atalhos de validacao e build.
- `worker/`: worker Python externo.
- `docs/`: documentacao operacional.

## Configurar variaveis de ambiente

Copie o arquivo de exemplo apenas para uso local:

```bash
cp .env.example .env
```

Nao commite `.env` com valores reais.

No ambiente principal da DevConsole, configure as variaveis pela propria
plataforma. A variavel mais importante e:

```text
DATABASE_URL=postgresql://usuario:senha@host:5432/temporal
```

Se o RDS/PostgreSQL exigir TLS:

```text
DATABASE_URL=postgresql://usuario:senha@host:5432/temporal?sslmode=require
```

Variaveis principais:

| Variavel | Obrigatoria | Uso |
| --- | --- | --- |
| `DATABASE_URL` | sim | URL PostgreSQL do store principal. |
| `TEMPORAL_VISIBILITY_DATABASE_URL` | nao | URL PostgreSQL do store de visibility. |
| `TEMPORAL_VISIBILITY_DB_NAME` | nao | Nome do banco de visibility quando usar o mesmo host de `DATABASE_URL`. Padrao: `temporal_visibility`. |
| `TEMPORAL_NAMESPACE` | nao | Namespace criado no bootstrap. Padrao: `default`. |
| `TEMPORAL_UI_PORT` | nao | Porta HTTP do UI. Padrao: `8080`; se ausente, usa `PORT` quando a plataforma fornecer. |
| `TEMPORAL_UI_PUBLIC_URL` | recomendado | URL publica do UI, usada para callback OIDC. |
| `TEMPORAL_AUTH_ENABLED` | nao | `true` para habilitar login OIDC no UI. Padrao: `false`. |
| `TEMPORAL_AUTH_PROVIDER_URL` | se OIDC | Provider URL OIDC. |
| `TEMPORAL_AUTH_ISSUER_URL` | se OIDC | Issuer URL OIDC. |
| `TEMPORAL_AUTH_CLIENT_ID` | se OIDC | Client ID do UI. |
| `TEMPORAL_AUTH_CLIENT_SECRET` | se OIDC | Secret do client OIDC. |
| `TEMPORAL_SKIP_SCHEMA_SETUP` | nao | `true` para nao aplicar schema no start. |

Tambem e possivel usar variaveis separadas em vez de URL:

```text
TEMPORAL_DB_HOST=meu-rds
TEMPORAL_DB_PORT=5432
TEMPORAL_DB_NAME=temporal
TEMPORAL_DB_USER=temporal
TEMPORAL_DB_PASSWORD=senha
TEMPORAL_DB_TLS_ENABLED=true
TEMPORAL_VISIBILITY_DB_NAME=temporal_visibility
```

## Preparar o banco PostgreSQL

O Temporal usa dois bancos:

```sql
CREATE DATABASE temporal;
CREATE DATABASE temporal_visibility;
```

O usuario da aplicacao precisa conseguir conectar e aplicar schema. O bootstrap
tambem tenta criar os bancos; se a plataforma ja provisionar os bancos, essa
tentativa e ignorada e o schema e aplicado em seguida.

Se o schema for gerenciado por outro processo, defina:

```text
TEMPORAL_SKIP_SCHEMA_SETUP=true
```

## Build da imagem principal

Para build local:

```bash
make devconsole-build
```

Comando equivalente:

```bash
docker build -t temporal-devconsole:local .
```

A imagem gerada expoe:

- `8080`: Temporal UI;
- `7233`: Temporal frontend gRPC.

Mantenha `7233` privado. Workers e SDK clients devem acessar essa porta por
rede privada, VPN, Tailscale, PrivateLink ou mecanismo equivalente.

## Rodar localmente com PostgreSQL em Docker

Crie uma rede:

```bash
docker network create temporal-devconsole
```

Suba um PostgreSQL descartavel:

```bash
docker run -d --name temporal-devconsole-postgres --network temporal-devconsole \
  -e POSTGRES_USER=temporal \
  -e POSTGRES_PASSWORD=temporal \
  postgres:16
```

Suba a aplicacao:

```bash
docker run --rm --name temporal-devconsole-app --network temporal-devconsole \
  -p 8080:8080 \
  -p 7233:7233 \
  -e DATABASE_URL=postgresql://temporal:temporal@temporal-devconsole-postgres:5432/temporal \
  -e TEMPORAL_VISIBILITY_DB_NAME=temporal_visibility \
  temporal-devconsole:local
```

Acesse:

```text
http://localhost:8080
```

Teste a saude do cluster:

```bash
docker exec temporal-devconsole-app temporal operator cluster health --address 127.0.0.1:7233
```

Resultado esperado:

```text
SERVING
```

Verifique o namespace:

```bash
docker exec temporal-devconsole-app temporal operator namespace describe -n default --address 127.0.0.1:7233
```

Limpeza do ambiente local:

```bash
docker rm -f temporal-devconsole-app temporal-devconsole-postgres
docker network rm temporal-devconsole
```

## Deploy na DevConsole

Na DevConsole, configure o projeto para:

1. usar o `Dockerfile` da raiz;
2. executar o container com o `ENTRYPOINT` padrao da imagem;
3. expor a porta HTTP `8080` ou a porta indicada por `TEMPORAL_UI_PORT`;
4. manter a porta gRPC `7233` privada;
5. injetar as variaveis de ambiente no ambiente principal.

Variaveis minimas:

```text
DATABASE_URL=postgresql://usuario:senha@host:5432/temporal?sslmode=require
TEMPORAL_VISIBILITY_DB_NAME=temporal_visibility
TEMPORAL_NAMESPACE=default
TEMPORAL_UI_PUBLIC_URL=https://url-do-temporal-ui
```

Com OIDC:

```text
TEMPORAL_AUTH_ENABLED=true
TEMPORAL_AUTH_PROVIDER_URL=https://idp.example.com/realms/temporal
TEMPORAL_AUTH_ISSUER_URL=https://idp.example.com/realms/temporal
TEMPORAL_AUTH_CLIENT_ID=temporal-ui
TEMPORAL_AUTH_CLIENT_SECRET=valor-secreto
```

Depois do deploy, valide:

- o container iniciou sem erro;
- o log mostra setup de schema;
- o log mostra start do Temporal Server;
- o log mostra start do Temporal UI;
- `GET /healthz` no UI retorna `{"status":"OK"}`;
- o endpoint gRPC privado responde para workers.

## Usar o Temporal UI

Abra a URL configurada em `TEMPORAL_UI_PUBLIC_URL` ou a URL publicada pela
DevConsole.

No UI voce pode:

- visualizar workflows;
- pesquisar execucoes;
- acompanhar historico de eventos;
- inspecionar falhas;
- iniciar workflows, se as acoes de escrita estiverem habilitadas;
- cancelar, terminar ou sinalizar workflows quando permitido.

Se OIDC estiver habilitado, o botao de login deve redirecionar para o provedor
de identidade e retornar para:

```text
<TEMPORAL_UI_PUBLIC_URL>/auth/sso/callback
```

## Instalar dependencias do worker

O worker fica fora da DevConsole. Em Linux/macOS:

```bash
cd worker
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m pip check
```

Em Windows PowerShell:

```powershell
cd worker
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m pip check
```

## Configurar o worker

Crie o `.env` do worker:

```bash
cd worker
cp .env.example .env
```

Variaveis principais do worker:

```text
TEMPORAL_ADDRESS=host-privado:7233
TEMPORAL_NAMESPACE=default
TEMPORAL_TASK_QUEUE=default-task-queue
TEMPORAL_WORKER_IDENTITY=worker-local
TEMPORAL_TLS_ENABLED=false
```

Se o endpoint privado usar TLS/mTLS:

```text
TEMPORAL_TLS_ENABLED=true
TEMPORAL_TLS_CA_FILE=/caminho/ca.pem
TEMPORAL_TLS_CLIENT_CERT_FILE=/caminho/client.pem
TEMPORAL_TLS_CLIENT_KEY_FILE=/caminho/client.key
```

Se houver autorizacao JWT no Temporal Server:

```text
TEMPORAL_AUTH_TOKEN=token
```

## Rodar o worker

Linux/macOS:

```bash
cd worker
set -a
source .env
set +a
.venv/bin/python -m temporal_worker.worker
```

Windows PowerShell:

```powershell
cd worker
$env:TEMPORAL_ADDRESS = "host-privado:7233"
$env:TEMPORAL_NAMESPACE = "default"
$env:TEMPORAL_TASK_QUEUE = "default-task-queue"
$env:TEMPORAL_WORKER_IDENTITY = "worker-windows"
.\.venv\Scripts\python.exe -m temporal_worker.worker
```

O worker deve ficar rodando e escutando a task queue configurada.

## Disparar workflow de teste

Com o worker em execucao, rode o client de exemplo.

Linux/macOS:

```bash
cd worker
set -a
source .env
set +a
.venv/bin/python -m temporal_worker.client Eduardo
```

Windows PowerShell:

```powershell
cd worker
$env:TEMPORAL_ADDRESS = "host-privado:7233"
$env:TEMPORAL_NAMESPACE = "default"
$env:TEMPORAL_TASK_QUEUE = "default-task-queue"
.\.venv\Scripts\python.exe -m temporal_worker.client Eduardo
```

Depois abra o Temporal UI e procure a execucao criada.

## Instalar o worker como servico no Windows

Instale o NSSM:

```powershell
winget install NSSM.NSSM
```

Registre o servico:

```powershell
cd worker
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\install-windows-service.ps1 `
  -ServiceName "TemporalPythonWorker" `
  -EnvFile ".\.env"
```

Validar:

```powershell
Get-Service TemporalPythonWorker
Get-Content .\logs\TemporalPythonWorker.out.log -Tail 80
Get-Content .\logs\TemporalPythonWorker.err.log -Tail 80
```

## Validacao local do repositorio

Antes de publicar alteracoes, rode:

```bash
make validate
```

Para a validacao estendida:

```bash
make validate-full
```

O `make validate` cobre:

- sintaxe dos scripts shell;
- instalacao e compilacao do worker Python;
- renderizacao de templates;
- validacao JSON/Python;
- build da imagem principal da DevConsole;
- build da imagem Keycloak.

O `make validate-full` tambem renderiza o chart Helm legado e roda checks
adicionais de workflows e manifests.

## Stack local completo sem DevConsole

Para testar o stack local antigo com Docker Compose:

```bash
make local-full
```

Servicos locais:

- Temporal UI: `http://localhost:8080`;
- Temporal gRPC: `localhost:7233`;
- Keycloak local: `http://keycloak.localhost:8081`;
- login local: `temporal.admin` / `temporal-admin`.

Para parar:

```bash
make local-down
```

Para remover volumes:

```bash
make local-clean
```

## Caminho legado EKS

O runtime principal e DevConsole. O caminho EKS permanece no repositorio para
ambientes que ainda precisem dele.

Documentos relacionados:

- [Runbook de deploy EKS](deploy-runbook.md)
- [Bootstrap AWS](aws-bootstrap.md)
- [GitHub Actions](github-actions-setup.md)
- [SSO Keycloak](sso-keycloak.md)

## Operacao e manutencao

Checks uteis no container:

```bash
temporal operator cluster health --address 127.0.0.1:7233
temporal operator namespace describe -n default --address 127.0.0.1:7233
curl -fsS http://127.0.0.1:8080/healthz
```

Logs importantes:

- inicio do `devconsole/start.sh`;
- espera pelo PostgreSQL;
- criacao/atualizacao de schema;
- start do Temporal Server;
- criacao do namespace;
- start do Temporal UI.

Quando alterar versoes:

1. ajuste os `ARG` do `Dockerfile` ou as variaveis de build da plataforma;
2. rode `make validate`;
3. rode um smoke test local com PostgreSQL;
4. publique na DevConsole.

## Problemas comuns

### O container nao inicia por falta de variavel

Confira se `DATABASE_URL` ou as variaveis `TEMPORAL_DB_*` foram definidas no
ambiente principal da DevConsole.

### Erro de conexao com PostgreSQL

Verifique:

- host e porta do banco;
- security group/firewall;
- usuario e senha;
- exigencia de TLS;
- `sslmode=require` na URL quando necessario.

### Erro de schema

Confirme se o usuario tem permissao para criar/alterar tabelas. Se o schema for
gerenciado fora da aplicacao, defina `TEMPORAL_SKIP_SCHEMA_SETUP=true`.

### UI abre, mas worker nao conecta

O UI usa HTTP; o worker usa gRPC na porta `7233`. Garanta que o worker tem rota
privada para o endpoint gRPC e que `TEMPORAL_ADDRESS` aponta para esse host.

### Login OIDC retorna erro de callback

Confira:

- `TEMPORAL_UI_PUBLIC_URL`;
- `TEMPORAL_AUTH_CALLBACK_URL`, se configurado manualmente;
- callback cadastrado no IdP;
- `TEMPORAL_AUTH_PROVIDER_URL`;
- `TEMPORAL_AUTH_ISSUER_URL`;
- `TEMPORAL_AUTH_CLIENT_ID`;
- `TEMPORAL_AUTH_CLIENT_SECRET`.

### Workflow fica pendente

Verifique se o worker esta rodando e se usa a mesma task queue do client:

```text
TEMPORAL_TASK_QUEUE=default-task-queue
```

## Seguranca

- Nao commite `.env` com valores reais.
- Guarde senhas e secrets na ferramenta de secrets da DevConsole.
- Mantenha `7233` privado.
- Use TLS para RDS/PostgreSQL quando disponivel.
- Use OIDC no UI em ambientes compartilhados.
- Se expor gRPC para fora da rede privada, adicione mTLS ou autorizacao propria.

## Proximo passo recomendado

Para instalar em ambiente real, comece pela DevConsole:

1. configure o build do `Dockerfile`;
2. configure `DATABASE_URL`;
3. configure `TEMPORAL_VISIBILITY_DB_NAME`;
4. configure a URL publica do UI;
5. publique;
6. valide `/healthz`;
7. configure o worker externo com o endpoint gRPC privado.
