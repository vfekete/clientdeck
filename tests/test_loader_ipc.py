from __future__ import annotations

import socket as real_socket
from types import SimpleNamespace

from clientdeck import loader_ipc


class _FakeSocket:
    def __init__(self, connect_should_fail: bool = False, sendall_should_fail: bool = False):
        self.connect_should_fail = connect_should_fail
        self.sendall_should_fail = sendall_should_fail
        self.connected_to = None
        self.sent: list[bytes] = []
        self.closed = False

    def connect(self, path):
        if self.connect_should_fail:
            raise OSError("connection refused")
        self.connected_to = path

    def sendall(self, data):
        if self.sendall_should_fail:
            raise OSError("broken pipe")
        self.sent.append(data)

    def close(self):
        self.closed = True


def _fake_socket_module(factory):
    return SimpleNamespace(socket=factory, AF_UNIX=real_socket.AF_UNIX, SOCK_STREAM=real_socket.SOCK_STREAM)


def test_null_handle_methods_are_all_safe_no_ops():
    handle = loader_ipc.LoaderHandle(None)
    handle.send_starting()
    handle.send_running()
    handle.close()


def test_send_after_sendall_failure_becomes_a_no_op():
    sock = _FakeSocket(sendall_should_fail=True)
    handle = loader_ipc.LoaderHandle(sock)

    handle.send_starting()
    assert sock.sent == []

    handle.send_running()
    assert sock.sent == []


def test_close_swallows_errors_and_is_idempotent():
    class _RaisingCloseSocket(_FakeSocket):
        def close(self):
            raise OSError("already closed")

    handle = loader_ipc.LoaderHandle(_RaisingCloseSocket())
    handle.close()
    handle.close()


def test_maybe_launch_loader_skips_when_not_packaged(monkeypatch):
    monkeypatch.setattr(loader_ipc, "is_packaged_build", lambda: False)

    handle = loader_ipc.maybe_launch_loader()

    assert handle._sock is None


def test_maybe_launch_loader_connects_without_launching_when_socket_env_already_set(monkeypatch):
    # A wrapper script (e.g. run.sh) already started its own loader and
    # set the channel up — see docs/comments-details.md [115]. The app
    # must connect to it, not spawn a second loader process.
    monkeypatch.setattr(loader_ipc, "is_packaged_build", lambda: True)
    monkeypatch.setenv(loader_ipc.SOCKET_ENV_VAR, "/tmp/already-set.sock")

    def _fail_if_called(*args, **kwargs):
        raise AssertionError("must not launch a second loader process")

    monkeypatch.setattr(loader_ipc.subprocess, "Popen", _fail_if_called)
    fake_sock = _FakeSocket()
    monkeypatch.setattr(loader_ipc, "socket", _fake_socket_module(lambda *a, **k: fake_sock))

    handle = loader_ipc.maybe_launch_loader()

    assert handle._sock is fake_sock
    assert fake_sock.connected_to == "/tmp/already-set.sock"
    assert fake_sock.sent == [b"starting\n"]


def test_maybe_launch_loader_connects_to_existing_socket_even_outside_a_packaged_build(monkeypatch):
    # The whole point of this env-var-first check: a source-checkout dev
    # run via a wrapper script still gets the splash — see [115].
    monkeypatch.setattr(loader_ipc, "is_packaged_build", lambda: False)
    monkeypatch.setenv(loader_ipc.SOCKET_ENV_VAR, "/tmp/dev-wrapper.sock")
    fake_sock = _FakeSocket()
    monkeypatch.setattr(loader_ipc, "socket", _fake_socket_module(lambda *a, **k: fake_sock))

    handle = loader_ipc.maybe_launch_loader()

    assert handle._sock is fake_sock
    assert fake_sock.sent == [b"starting\n"]


def test_maybe_launch_loader_null_handle_when_existing_socket_unreachable(monkeypatch):
    monkeypatch.setattr(loader_ipc, "is_packaged_build", lambda: True)
    monkeypatch.setenv(loader_ipc.SOCKET_ENV_VAR, "/tmp/nothing-listening.sock")
    monkeypatch.setattr(
        loader_ipc, "socket", _fake_socket_module(lambda *a, **k: _FakeSocket(connect_should_fail=True))
    )
    monkeypatch.setattr(loader_ipc.time, "sleep", lambda *_: None)

    handle = loader_ipc.maybe_launch_loader()

    assert handle._sock is None


def test_maybe_launch_loader_skips_when_binary_missing(monkeypatch, tmp_path):
    monkeypatch.setattr(loader_ipc, "is_packaged_build", lambda: True)
    monkeypatch.delenv(loader_ipc.SOCKET_ENV_VAR, raising=False)
    monkeypatch.setattr(loader_ipc, "get_loader_path", lambda: tmp_path / "does-not-exist")

    handle = loader_ipc.maybe_launch_loader()

    assert handle._sock is None


def test_maybe_launch_loader_skips_when_popen_fails(monkeypatch, tmp_path):
    loader_bin = tmp_path / "clientdeck-loader"
    loader_bin.write_text("#!/bin/sh\n")
    monkeypatch.setattr(loader_ipc, "is_packaged_build", lambda: True)
    monkeypatch.delenv(loader_ipc.SOCKET_ENV_VAR, raising=False)
    monkeypatch.setattr(loader_ipc, "get_loader_path", lambda: loader_bin)

    def _raise(*args, **kwargs):
        raise OSError("no such file")

    monkeypatch.setattr(loader_ipc.subprocess, "Popen", _raise)

    handle = loader_ipc.maybe_launch_loader()

    assert handle._sock is None


def test_maybe_launch_loader_skips_when_connect_never_succeeds(monkeypatch, tmp_path):
    loader_bin = tmp_path / "clientdeck-loader"
    loader_bin.write_text("#!/bin/sh\n")
    monkeypatch.setattr(loader_ipc, "is_packaged_build", lambda: True)
    monkeypatch.delenv(loader_ipc.SOCKET_ENV_VAR, raising=False)
    monkeypatch.setattr(loader_ipc, "get_loader_path", lambda: loader_bin)
    monkeypatch.setattr(loader_ipc.subprocess, "Popen", lambda *a, **k: SimpleNamespace())
    monkeypatch.setattr(
        loader_ipc, "socket", _fake_socket_module(lambda *a, **k: _FakeSocket(connect_should_fail=True))
    )
    monkeypatch.setattr(loader_ipc.time, "sleep", lambda *_: None)

    handle = loader_ipc.maybe_launch_loader()

    assert handle._sock is None


def test_maybe_launch_loader_success_sends_starting(monkeypatch, tmp_path):
    loader_bin = tmp_path / "clientdeck-loader"
    loader_bin.write_text("#!/bin/sh\n")
    monkeypatch.setattr(loader_ipc, "is_packaged_build", lambda: True)
    monkeypatch.delenv(loader_ipc.SOCKET_ENV_VAR, raising=False)
    monkeypatch.setattr(loader_ipc, "get_loader_path", lambda: loader_bin)

    launched = {}

    def _fake_popen(argv, **kwargs):
        launched["argv"] = argv
        launched["env"] = kwargs.get("env")
        return SimpleNamespace()

    monkeypatch.setattr(loader_ipc.subprocess, "Popen", _fake_popen)
    fake_sock = _FakeSocket()
    monkeypatch.setattr(loader_ipc, "socket", _fake_socket_module(lambda *a, **k: fake_sock))

    handle = loader_ipc.maybe_launch_loader()

    assert handle._sock is fake_sock
    assert fake_sock.sent == [b"starting\n"]
    assert launched["argv"] == [str(loader_bin)]
    assert loader_ipc.SOCKET_ENV_VAR in launched["env"]


def test_maybe_launch_loader_chmods_the_binary(monkeypatch, tmp_path):
    loader_bin = tmp_path / "clientdeck-loader"
    loader_bin.write_text("#!/bin/sh\n")
    loader_bin.chmod(0o644)
    monkeypatch.setattr(loader_ipc, "is_packaged_build", lambda: True)
    monkeypatch.delenv(loader_ipc.SOCKET_ENV_VAR, raising=False)
    monkeypatch.setattr(loader_ipc, "get_loader_path", lambda: loader_bin)
    monkeypatch.setattr(loader_ipc.subprocess, "Popen", lambda *a, **k: SimpleNamespace())
    monkeypatch.setattr(loader_ipc, "socket", _fake_socket_module(lambda *a, **k: _FakeSocket()))

    loader_ipc.maybe_launch_loader()

    assert loader_bin.stat().st_mode & 0o111
