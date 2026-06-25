#!/usr/bin/env python3
import shlex
import sys
from urllib.parse import parse_qs, unquote, urlparse


def fail(message: str) -> None:
    print(f"parse_database_url.py: {message}", file=sys.stderr)
    sys.exit(2)


def emit(assignments: dict[str, str]) -> None:
    for key, value in assignments.items():
        print(f"{key}={shlex.quote(value)}")


def parse_bool_sslmode(url) -> str:
    sslmode = parse_qs(url.query).get("sslmode", [""])[0].lower()
    return "true" if sslmode in {"require", "verify-ca", "verify-full"} else "false"


def main() -> None:
    if len(sys.argv) != 3 or sys.argv[1] not in {"default", "visibility"}:
        fail("usage: parse_database_url.py default|visibility postgresql://user:pass@host:port/database")

    mode = sys.argv[1]
    raw_url = sys.argv[2]
    url = urlparse(raw_url)

    if url.scheme not in {"postgres", "postgresql"}:
        fail("only postgres/postgresql URLs are supported")
    if not url.hostname:
        fail("database URL must include a host")
    if not url.username:
        fail("database URL must include a username")
    if url.password is None:
        fail("database URL must include a password")

    database = unquote(url.path.lstrip("/").split("/", 1)[0])
    if not database:
        fail("database URL must include a database name")

    port = str(url.port or 5432)
    username = unquote(url.username)
    password = unquote(url.password)
    host = url.hostname
    tls = parse_bool_sslmode(url)

    if mode == "default":
        emit(
            {
                "DB": "postgres12",
                "DBNAME": database,
                "POSTGRES_SEEDS": host,
                "DB_PORT": port,
                "POSTGRES_USER": username,
                "POSTGRES_PWD": password,
                "SQL_TLS_ENABLED": tls,
                "SQL_TLS": tls,
            }
        )
        return

    assignments = {
        "VISIBILITY_DBNAME": database,
        "VISIBILITY_POSTGRES_SEEDS": host,
        "VISIBILITY_DB_PORT": port,
        "VISIBILITY_POSTGRES_USER": username,
        "VISIBILITY_POSTGRES_PWD": password,
    }
    if tls == "true":
        assignments["SQL_TLS_ENABLED"] = "true"
        assignments["SQL_TLS"] = "true"
    emit(assignments)


if __name__ == "__main__":
    main()
