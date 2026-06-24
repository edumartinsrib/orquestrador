from datetime import datetime, timezone

from temporalio import activity


@activity.defn(name="say_hello")
async def say_hello(name: str) -> str:
    processed_at = datetime.now(timezone.utc).isoformat()
    return f"Hello, {name}. Python worker processed this activity at {processed_at}."

