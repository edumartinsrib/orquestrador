#!/usr/bin/env python3
import os
import sys
from pathlib import Path

from playwright.sync_api import TimeoutError as PlaywrightTimeoutError
from playwright.sync_api import sync_playwright


def read_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip("\"'")
    return values


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    env = read_env_file(repo_root / "local" / ".env.local")

    temporal_url = env.get("TEMPORAL_UI_PUBLIC_URL", "http://localhost:8080").rstrip("/")
    username = env["TEMPORAL_INITIAL_ADMIN_USERNAME"]
    password = env["TEMPORAL_INITIAL_ADMIN_PASSWORD"]

    chrome_path = os.environ.get("CHROME_PATH", "/usr/bin/google-chrome")

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            headless=True,
            executable_path=chrome_path,
            args=["--no-sandbox"],
        )
        page = browser.new_page()

        try:
            unauthenticated = page.request.get(f"{temporal_url}/api/v1/namespaces")
            if unauthenticated.status != 401:
                raise RuntimeError(
                    f"expected unauthenticated namespace API status 401, got {unauthenticated.status}"
                )

            page.goto(f"{temporal_url}/auth/sso", wait_until="domcontentloaded", timeout=30000)
            page.fill('input[name="username"]', username)
            page.fill('input[name="password"]', password)

            with page.expect_response(
                lambda response: response.url.startswith(f"{temporal_url}/api/v1/namespaces")
                and response.status == 200,
                timeout=30000,
            ) as authenticated_response:
                page.click('input[type="submit"], button[type="submit"]')

            response = authenticated_response.value

            try:
                page.wait_for_url(f"{temporal_url}/**", timeout=30000)
                page.wait_for_load_state("networkidle", timeout=30000)
            except PlaywrightTimeoutError:
                pass

            if not page.url.startswith(temporal_url):
                raise RuntimeError(f"SSO did not return to Temporal UI; current URL is {page.url}")

            print("OK: Temporal UI browser SSO login")
            print(f"OK: authenticated namespace API status {response.status}")
        finally:
            browser.close()

    return 0


if __name__ == "__main__":
    sys.exit(main())
