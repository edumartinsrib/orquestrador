# Worker Temporal Python Local

Worker de exemplo em Python para rodar em uma maquina local, inclusive Windows, conectado ao Temporal local, ao Temporal hospedado na DevConsole ou ao caminho legado no EKS.

Este worker nao e implantado no Kubernetes. Ele escuta a task queue configurada em `TEMPORAL_TASK_QUEUE` e executa o workflow de exemplo `GreetingWorkflow`.

## Estrutura

- `temporal_worker/worker.py`: processo do worker.
- `temporal_worker/client.py`: cliente de teste que dispara um workflow.
- `temporal_worker/workflows.py`: workflow de exemplo.
- `temporal_worker/activities.py`: activity de exemplo.
- `scripts/install-windows-service.ps1`: instalador para rodar o worker como servico Windows via NSSM.
- `.env.example`: variaveis para conexao com Temporal.

## Desenvolvimento local no Windows

### 1. Instalar ferramentas

No PowerShell como administrador:

```powershell
winget install Python.Python.3.12
winget install Git.Git
```

Instale o Temporal CLI para testes locais:

```powershell
$zip = "$env:TEMP\temporal-cli.zip"
Invoke-WebRequest "https://temporal.download/cli/archive/latest?platform=windows&arch=amd64" -OutFile $zip
Expand-Archive $zip "$env:USERPROFILE\temporal-cli" -Force
setx PATH "$env:PATH;$env:USERPROFILE\temporal-cli"
```

Abra um novo terminal e valide:

```powershell
python --version
pip --version
temporal --version
```

### 2. Subir Temporal local para teste

```powershell
temporal server start-dev --ui-port 8233
```

O gRPC local fica em `localhost:7233` e o UI em `http://localhost:8233`.

### 3. Rodar o worker Python

Em outro PowerShell:

```powershell
cd worker
Copy-Item .env.example .env
notepad .env

python -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m pip check

$env:TEMPORAL_ADDRESS = "localhost:7233"
$env:TEMPORAL_NAMESPACE = "default"
$env:TEMPORAL_TASK_QUEUE = "default-task-queue"
.\.venv\Scripts\python.exe -m temporal_worker.worker
```

### 4. Disparar workflow de teste

Em outro terminal:

```powershell
cd worker
$env:TEMPORAL_ADDRESS = "localhost:7233"
$env:TEMPORAL_NAMESPACE = "default"
$env:TEMPORAL_TASK_QUEUE = "default-task-queue"
.\.venv\Scripts\python.exe -m temporal_worker.client Eduardo
```

## Instalar como servico do Windows

Instale NSSM:

```powershell
winget install NSSM.NSSM
```

Depois rode, como administrador:

```powershell
cd worker
Copy-Item .env.example .env
notepad .env

Set-ExecutionPolicy -Scope Process Bypass
.\scripts\install-windows-service.ps1 `
  -ServiceName "TemporalPythonWorker" `
  -EnvFile ".\.env"
```

O script cria `.venv`, instala `requirements.txt`, registra `python -m temporal_worker.worker` com NSSM, inicia automaticamente no boot e grava logs em `.\logs` por padrao:

```powershell
Get-Service TemporalPythonWorker
Get-Content .\logs\TemporalPythonWorker.out.log -Tail 80
Get-Content .\logs\TemporalPythonWorker.err.log -Tail 80
```

Para escolher outro local de logs:

```powershell
.\scripts\install-windows-service.ps1 `
  -ServiceName "TemporalPythonWorker" `
  -EnvFile ".\.env" `
  -LogDirectory "C:\TemporalPythonWorker\logs"
```

## Conectar ao Temporal remoto

O endpoint gRPC do Temporal deve ficar privado. Para uma maquina local acessar o Temporal na DevConsole, use o endpoint privado fornecido pela plataforma, VPN, Tailscale, Direct Connect ou PrivateLink.

No caminho legado EKS, um `kubectl port-forward` administrativo tambem pode ser usado:

```powershell
kubectl -n temporal port-forward svc/temporal-frontend 7233:7233
```

Com port-forward, configure no `.env`:

```powershell
TEMPORAL_ADDRESS=localhost:7233
TEMPORAL_NAMESPACE=default
TEMPORAL_TASK_QUEUE=default-task-queue
TEMPORAL_WORKER_IDENTITY=meu-pc-python-worker
TEMPORAL_TLS_ENABLED=false
```

Se expuser um endpoint TLS privado, configure:

```powershell
TEMPORAL_TLS_ENABLED=true
TEMPORAL_TLS_CA_FILE=C:\Temporal\certs\ca.pem
TEMPORAL_TLS_CLIENT_CERT_FILE=C:\Temporal\certs\client.pem
TEMPORAL_TLS_CLIENT_KEY_FILE=C:\Temporal\certs\client.key
```

## Variaveis do worker

- `TEMPORAL_ADDRESS`: endereco gRPC do Temporal, exemplo `localhost:7233`.
- `TEMPORAL_NAMESPACE`: namespace Temporal, padrao `default`.
- `TEMPORAL_TASK_QUEUE`: task queue escutada pelo worker.
- `TEMPORAL_WORKER_IDENTITY`: identidade exibida nos logs do Temporal.
- `TEMPORAL_TLS_ENABLED`: `true` para conexao TLS.
- `TEMPORAL_TLS_CA_FILE`: CA para TLS, opcional.
- `TEMPORAL_TLS_CLIENT_CERT_FILE`: certificado client mTLS, opcional.
- `TEMPORAL_TLS_CLIENT_KEY_FILE`: chave client mTLS, opcional.
- `TEMPORAL_AUTH_TOKEN`: bearer token opcional, caso voce habilite autorizacao JWT no Temporal Server.
