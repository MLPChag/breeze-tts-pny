"""Console and per-run JSON diagnostics without speech text or audio."""
import contextlib
import json
import logging

LOGGER = logging.getLogger('breeze_pny.events')
LOGGER.propagate = False


def event(name, **fields):
    payload = json.dumps({'event': name, **fields})
    print(payload, flush=True)
    LOGGER.info(payload)


@contextlib.contextmanager
def capture_events(path):
    handler = logging.FileHandler(path, mode='x', encoding='utf-8')
    handler.setFormatter(logging.Formatter('%(message)s'))
    previous = LOGGER.level
    LOGGER.setLevel(logging.INFO)
    LOGGER.addHandler(handler)
    try:
        yield
    finally:
        LOGGER.removeHandler(handler)
        handler.close()
        LOGGER.setLevel(previous)
