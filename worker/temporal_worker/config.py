import os
from dataclasses import dataclass
from pathlib import Path

from temporalio.client import TLSConfig


@dataclass(frozen=True)
class WorkerConfig:
    address: str
    namespace: str
    task_queue: str
    identity: str
    tls_enabled: bool
    tls_ca_file: str | None
    tls_client_cert_file: str | None
    tls_client_key_file: str | None
    auth_token: str | None

    @property
    def rpc_metadata(self) -> dict[str, str]:
        if not self.auth_token:
            return {}
        return {"authorization": f"Bearer {self.auth_token}"}

    @property
    def tls_config(self) -> bool | TLSConfig:
        if not self.tls_enabled:
            return False

        server_root_ca_cert = _read_file_if_set(self.tls_ca_file)
        client_cert = _read_file_if_set(self.tls_client_cert_file)
        client_private_key = _read_file_if_set(self.tls_client_key_file)

        if client_cert and not client_private_key:
            raise ValueError("TEMPORAL_TLS_CLIENT_KEY_FILE is required when TEMPORAL_TLS_CLIENT_CERT_FILE is set")
        if client_private_key and not client_cert:
            raise ValueError("TEMPORAL_TLS_CLIENT_CERT_FILE is required when TEMPORAL_TLS_CLIENT_KEY_FILE is set")

        if server_root_ca_cert or client_cert or client_private_key:
            return TLSConfig(
                server_root_ca_cert=server_root_ca_cert,
                client_cert=client_cert,
                client_private_key=client_private_key,
            )

        return True


def get_worker_config() -> WorkerConfig:
    return WorkerConfig(
        address=_read_env("TEMPORAL_ADDRESS", "localhost:7233"),
        namespace=_read_env("TEMPORAL_NAMESPACE", "default"),
        task_queue=_read_env("TEMPORAL_TASK_QUEUE", "default-task-queue"),
        identity=_read_env("TEMPORAL_WORKER_IDENTITY", f"python-worker-{os.getpid()}"),
        tls_enabled=_read_bool("TEMPORAL_TLS_ENABLED", False),
        tls_ca_file=_read_optional_env("TEMPORAL_TLS_CA_FILE"),
        tls_client_cert_file=_read_optional_env("TEMPORAL_TLS_CLIENT_CERT_FILE"),
        tls_client_key_file=_read_optional_env("TEMPORAL_TLS_CLIENT_KEY_FILE"),
        auth_token=_read_optional_env("TEMPORAL_AUTH_TOKEN"),
    )


def _read_env(name: str, fallback: str | None = None) -> str:
    value = os.getenv(name)
    if value is not None and value.strip():
        return value.strip()
    if fallback is not None:
        return fallback
    raise ValueError(f"Missing required environment variable {name}")


def _read_optional_env(name: str) -> str | None:
    value = os.getenv(name)
    if value is None or not value.strip():
        return None
    return value.strip()


def _read_bool(name: str, fallback: bool) -> bool:
    value = os.getenv(name)
    if value is None or not value.strip():
        return fallback
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _read_file_if_set(path: str | None) -> bytes | None:
    if not path:
        return None
    return Path(path).read_bytes()
