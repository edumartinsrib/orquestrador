import asyncio
import json
import signal

from temporalio.client import Client
from temporalio.worker import Worker

from temporal_worker.activities import say_hello
from temporal_worker.config import get_worker_config
from temporal_worker.workflows import GreetingWorkflow


async def main() -> None:
    config = get_worker_config()
    client = await Client.connect(
        config.address,
        namespace=config.namespace,
        identity=config.identity,
        rpc_metadata=config.rpc_metadata,
        tls=config.tls_config,
    )

    worker = Worker(
        client,
        task_queue=config.task_queue,
        workflows=[GreetingWorkflow],
        activities=[say_hello],
    )

    stop_event = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stop_event.set)
        except NotImplementedError:
            signal.signal(sig, lambda *_: stop_event.set())

    print(
        json.dumps(
            {
                "message": "Python Temporal worker started",
                "address": config.address,
                "namespace": config.namespace,
                "taskQueue": config.task_queue,
                "identity": config.identity,
                "tlsEnabled": config.tls_enabled,
            },
            sort_keys=True,
        ),
        flush=True,
    )

    worker_task = asyncio.create_task(worker.run())
    stop_task = asyncio.create_task(stop_event.wait())
    done, pending = await asyncio.wait(
        {worker_task, stop_task},
        return_when=asyncio.FIRST_COMPLETED,
    )

    if stop_task in done and not worker_task.done():
        worker_task.cancel()
        await asyncio.gather(worker_task, return_exceptions=True)
    else:
        await worker_task

    for task in pending:
        task.cancel()


if __name__ == "__main__":
    asyncio.run(main())

