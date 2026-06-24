param(
  [string]$ServiceName = "TemporalPythonWorker",
  [string]$ProjectPath = (Resolve-Path "$PSScriptRoot\..").Path,
  [string]$EnvFile = "",
  [string]$LogDirectory = "",
  [string]$PythonExe = "",
  [string]$TemporalAddress = "",
  [string]$TemporalNamespace = "",
  [string]$TaskQueue = "",
  [string]$WorkerIdentity = "",
  [string]$TlsEnabled = "",
  [string]$TlsCaFile = "",
  [string]$TlsClientCertFile = "",
  [string]$TlsClientKeyFile = "",
  [string]$AuthToken = ""
)

$ErrorActionPreference = "Stop"

$ProjectPath = (Resolve-Path $ProjectPath).Path

if (-not $EnvFile) {
  $EnvFile = Join-Path $ProjectPath ".env"
}

if (-not $LogDirectory) {
  $LogDirectory = Join-Path $ProjectPath "logs"
}
$LogDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogDirectory)
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null

if (-not (Test-Path (Join-Path $ProjectPath "requirements.txt"))) {
  throw "ProjectPath does not look like the Python worker folder: $ProjectPath"
}

$envValues = @{}
if (Test-Path $EnvFile) {
  Get-Content $EnvFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#")) {
      $parts = $line.Split("=", 2)
      if ($parts.Count -eq 2) {
        $key = $parts[0].Trim()
        $value = $parts[1].Trim()
        if (
          ($value.StartsWith('"') -and $value.EndsWith('"')) -or
          ($value.StartsWith("'") -and $value.EndsWith("'"))
        ) {
          $value = $value.Substring(1, $value.Length - 2)
        }

        $envValues[$key] = $value
      }
    }
  }
}

function Get-Setting {
  param(
    [string]$Name,
    [string]$ParameterValue,
    [string]$Fallback = ""
  )

  if ($ParameterValue) {
    return $ParameterValue
  }

  if ($envValues.ContainsKey($Name) -and $envValues[$Name]) {
    return $envValues[$Name]
  }

  return $Fallback
}

if (-not $PythonExe) {
  $pythonCommand = Get-Command py -ErrorAction SilentlyContinue
  if ($pythonCommand) {
    $PythonExe = $pythonCommand.Source
  } else {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCommand) {
      $PythonExe = $pythonCommand.Source
    }
  }
}

if (-not $PythonExe) {
  throw "Python was not found. Install Python 3 first: winget install Python.Python.3.12"
}

$nssm = (Get-Command nssm -ErrorAction SilentlyContinue).Source
if (-not $nssm) {
  throw "NSSM was not found. Install it first: winget install NSSM.NSSM"
}

$venvPath = Join-Path $ProjectPath ".venv"
$venvPython = Join-Path $venvPath "Scripts\python.exe"

if (-not (Test-Path $venvPython)) {
  if ((Split-Path -Leaf $PythonExe) -eq "py.exe") {
    & $PythonExe -3 -m venv $venvPath
  } else {
    & $PythonExe -m venv $venvPath
  }
}

& $venvPython -m pip install --upgrade pip
& $venvPython -m pip install -r (Join-Path $ProjectPath "requirements.txt")
& $venvPython -m pip check

$TemporalAddress = Get-Setting "TEMPORAL_ADDRESS" $TemporalAddress "localhost:7233"
$TemporalNamespace = Get-Setting "TEMPORAL_NAMESPACE" $TemporalNamespace "default"
$TaskQueue = Get-Setting "TEMPORAL_TASK_QUEUE" $TaskQueue "default-task-queue"
$WorkerIdentity = Get-Setting "TEMPORAL_WORKER_IDENTITY" $WorkerIdentity "$env:COMPUTERNAME-python-worker"
$TlsEnabled = Get-Setting "TEMPORAL_TLS_ENABLED" $TlsEnabled "false"
$TlsCaFile = Get-Setting "TEMPORAL_TLS_CA_FILE" $TlsCaFile ""
$TlsClientCertFile = Get-Setting "TEMPORAL_TLS_CLIENT_CERT_FILE" $TlsClientCertFile ""
$TlsClientKeyFile = Get-Setting "TEMPORAL_TLS_CLIENT_KEY_FILE" $TlsClientKeyFile ""
$AuthToken = Get-Setting "TEMPORAL_AUTH_TOKEN" $AuthToken ""

$stdoutLog = Join-Path $LogDirectory "$ServiceName.out.log"
$stderrLog = Join-Path $LogDirectory "$ServiceName.err.log"

$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
  & $nssm stop $ServiceName 2>$null | Out-Null
  & $nssm remove $ServiceName confirm | Out-Null
}

& $nssm install $ServiceName $venvPython "-m" "temporal_worker.worker" | Out-Null
& $nssm set $ServiceName AppDirectory $ProjectPath | Out-Null
& $nssm set $ServiceName AppEnvironmentExtra `
  "PYTHONUNBUFFERED=1" `
  "TEMPORAL_ADDRESS=$TemporalAddress" `
  "TEMPORAL_NAMESPACE=$TemporalNamespace" `
  "TEMPORAL_TASK_QUEUE=$TaskQueue" `
  "TEMPORAL_WORKER_IDENTITY=$WorkerIdentity" `
  "TEMPORAL_TLS_ENABLED=$TlsEnabled" `
  "TEMPORAL_TLS_CA_FILE=$TlsCaFile" `
  "TEMPORAL_TLS_CLIENT_CERT_FILE=$TlsClientCertFile" `
  "TEMPORAL_TLS_CLIENT_KEY_FILE=$TlsClientKeyFile" `
  "TEMPORAL_AUTH_TOKEN=$AuthToken" | Out-Null
& $nssm set $ServiceName AppStdout $stdoutLog | Out-Null
& $nssm set $ServiceName AppStderr $stderrLog | Out-Null
& $nssm set $ServiceName AppRotateFiles 1 | Out-Null
& $nssm set $ServiceName AppRotateOnline 1 | Out-Null
& $nssm set $ServiceName AppRotateSeconds 86400 | Out-Null
& $nssm set $ServiceName AppRotateBytes 10485760 | Out-Null
& $nssm set $ServiceName Start SERVICE_AUTO_START | Out-Null
& $nssm start $ServiceName | Out-Null

Write-Host "Service $ServiceName installed and started."
Write-Host "Python: $venvPython"
Write-Host "Logs:"
Write-Host "  stdout: $stdoutLog"
Write-Host "  stderr: $stderrLog"
