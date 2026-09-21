"""Talks to the compiled clientdeck-loader splash over its Unix-socket
protocol. Implements the "App-side responsibilities" section of
claude-blocks/python-qt-startup-splash.claude.md; see
docs/comments-details.md [110].
"""

from __future__ import annotations

import contextlib
import os
import socket
import subprocess
import tempfile
import time
from pathlib import Path

from .paths import get_loader_path, is_packaged_build

SOCKET_ENV_VAR = "CLIENTDECK_LOADER_SOCKET"
_CONNECT_RETRIES = 20
_CONNECT_RETRY_DELAY_S = 0.05


class LoaderHandle:
    """Every method is a best-effort no-op once `_sock` is None — see [111]."""

    def __init__(self, sock: socket.socket | None):
        self._sock = sock

    def send_starting(self) -> None:
        self._send(b"starting\n")

    def send_running(self) -> None:
        self._send(b"running\n")

    def _send(self, data: bytes) -> None:
        if self._sock is None:
            return
        try:
            self._sock.sendall(data)
        except OSError:
            self._sock = None

    def close(self) -> None:
        if self._sock is not None:
            with contextlib.suppress(OSError):
                self._sock.close()
            self._sock = None


_NULL_HANDLE = LoaderHandle(None)


def maybe_launch_loader() -> LoaderHandle:
    """Connect to an already-running loader, launch one ourselves, or
    return a no-op handle — see [112] for why/when this does nothing,
    and [115] for the two different ways a connection can come about."""
    existing_socket_path = os.environ.get(SOCKET_ENV_VAR)
    if existing_socket_path:
        return _connect_only(existing_socket_path)

    if not is_packaged_build():
        return _NULL_HANDLE
    loader_path = get_loader_path()
    if not loader_path.is_file():
        return _NULL_HANDLE
    with contextlib.suppress(OSError):
        os.chmod(loader_path, 0o755)

    socket_dir = tempfile.mkdtemp(prefix="clientdeck-loader-")
    socket_path = os.path.join(socket_dir, "loader.sock")
    env = {**os.environ, SOCKET_ENV_VAR: socket_path}
    try:
        subprocess.Popen(
            [str(loader_path)],
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        return _NULL_HANDLE

    return _connect_only(socket_path)


def _connect_only(socket_path: str) -> LoaderHandle:
    sock = _connect_with_retry(socket_path)
    if sock is None:
        return _NULL_HANDLE
    handle = LoaderHandle(sock)
    handle.send_starting()
    return handle


def _connect_with_retry(socket_path: str) -> socket.socket | None:
    # The loader binds/listens as its own first action, so this should
    # succeed almost immediately — retried anyway as the belt-and-suspenders
    # half of the blueprint's "race on channel setup" guidance.
    for _ in range(_CONNECT_RETRIES):
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.connect(socket_path)
            return sock
        except OSError:
            time.sleep(_CONNECT_RETRY_DELAY_S)
    return None
