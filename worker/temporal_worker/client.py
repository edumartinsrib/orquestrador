import asyncio
import sys
import time

from temporalio.client import Client

from temporal_worker.config import get_worker_config
from temporal_worker.workflows import GreetingWorkflow


async def main() -> None:
    config = get_worker_config()
    name = sys.argv[1] if len(sys.argv) > 1 else "Eduardo"

    client = await Client.connect(
        config.address,
        namespace=config.namespace,
        identity=f"{config.identity}-client",
        rpc_metadata=config.rpc_metadata,
        tls=config.tls_config,
    )

    handle = await client.start_workflow(
        GreetingWorkflow.run,
        name,
        id=f"greeting-{int(time.time() * 1000)}",
        task_queue=config.task_queue,
    )

    print(f"Started workflow {handle.id}")
    print(await handle.result())


if __name__ == "__main__":
    asyncio.run(main())

