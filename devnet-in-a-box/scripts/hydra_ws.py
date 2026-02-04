\
#!/usr/bin/env python3
"""Minimal WebSocket client for Hydra node API (no external deps).

Why this exists:
- Deterministic rehearsal scripts shouldn't depend on `websocat` being installed.
- Hydra node exposes a WebSocket API on the same `--api-port` (default 4001).
- We only need: send one JSON command (Init/Close/Fanout/NewTx) and/or wait for a tagged ServerOutput.

Supports:
- ws:// and wss://
- One-shot send
- Wait for any of N tags with timeout
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import select
import socket
import ssl
import sys
import time
from dataclasses import dataclass
from typing import Iterable, Tuple
from urllib.parse import urlparse

_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


class WsError(RuntimeError):
    pass


@dataclass
class WsUrl:
    scheme: str
    host: str
    port: int
    resource: str  # includes path + query


def parse_ws_url(url: str) -> WsUrl:
    u = urlparse(url)
    if u.scheme not in ("ws", "wss"):
        raise WsError(f"Unsupported URL scheme: {u.scheme!r} (expected ws/wss)")
    if not u.hostname:
        raise WsError("URL missing hostname")
    host = u.hostname
    port = u.port or (443 if u.scheme == "wss" else 80)
    path = u.path or "/"
    resource = path + ("?" + u.query if u.query else "")
    return WsUrl(u.scheme, host, port, resource)


def _read_exact(sock: socket.socket, n: int) -> bytes:
    buf = bytearray()
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise WsError("Socket closed unexpectedly")
        buf.extend(chunk)
    return bytes(buf)


def _make_accept(key_b64: str) -> str:
    h = hashlib.sha1((key_b64 + _GUID).encode("utf-8")).digest()
    return base64.b64encode(h).decode("ascii")


def ws_connect(url: WsUrl, *, timeout: float = 10.0, insecure_tls: bool = False) -> socket.socket:
    raw = socket.create_connection((url.host, url.port), timeout=timeout)
    sock: socket.socket
    if url.scheme == "wss":
        ctx = ssl.create_default_context()
        if insecure_tls:
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
        sock = ctx.wrap_socket(raw, server_hostname=url.host)
    else:
        sock = raw

    key = base64.b64encode(os.urandom(16)).decode("ascii")
    req = (
        f"GET {url.resource} HTTP/1.1\r\n"
        f"Host: {url.host}:{url.port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "User-Agent: devnet-in-a-box-rehearsal\r\n"
        "\r\n"
    ).encode("utf-8")
    sock.sendall(req)

    # Read HTTP response headers
    data = bytearray()
    while b"\r\n\r\n" not in data:
        chunk = sock.recv(4096)
        if not chunk:
            raise WsError("Handshake failed: connection closed")
        data.extend(chunk)
        if len(data) > 65536:
            raise WsError("Handshake failed: headers too large")
    header_bytes, _ = data.split(b"\r\n\r\n", 1)
    header_text = header_bytes.decode("iso-8859-1")
    lines = header_text.split("\r\n")
    if not lines or not lines[0].startswith("HTTP/1.1 101"):
        got = lines[0] if lines else ""
        raise WsError(f"Handshake failed: expected 101 Switching Protocols, got: {got}")
    headers = {}
    for line in lines[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            headers[k.strip().lower()] = v.strip()
    accept = headers.get("sec-websocket-accept")
    expected = _make_accept(key)
    if accept != expected:
        raise WsError("Handshake failed: Sec-WebSocket-Accept mismatch")
    return sock


def _send_frame(sock: socket.socket, opcode: int, payload: bytes) -> None:
    # Client-to-server frames MUST be masked.
    fin_opcode = 0x80 | (opcode & 0x0F)
    mask_key = os.urandom(4)
    length = len(payload)

    if length < 126:
        header = bytes([fin_opcode, 0x80 | length])
        ext = b""
    elif length < (1 << 16):
        header = bytes([fin_opcode, 0x80 | 126])
        ext = length.to_bytes(2, "big")
    else:
        header = bytes([fin_opcode, 0x80 | 127])
        ext = length.to_bytes(8, "big")

    masked = bytes(b ^ mask_key[i % 4] for i, b in enumerate(payload))
    sock.sendall(header + ext + mask_key + masked)


def ws_send_text(sock: socket.socket, text: str) -> None:
    _send_frame(sock, opcode=0x1, payload=text.encode("utf-8"))


def ws_send_close(sock: socket.socket) -> None:
    try:
        _send_frame(sock, opcode=0x8, payload=b"")
    except Exception:
        pass


def ws_send_pong(sock: socket.socket, payload: bytes) -> None:
    _send_frame(sock, opcode=0xA, payload=payload)


def _recv_frame(sock: socket.socket) -> Tuple[int, bytes]:
    # Returns (opcode, payload)
    b1, b2 = _read_exact(sock, 2)
    opcode = b1 & 0x0F
    masked = (b2 & 0x80) != 0
    length = b2 & 0x7F
    if length == 126:
        length = int.from_bytes(_read_exact(sock, 2), "big")
    elif length == 127:
        length = int.from_bytes(_read_exact(sock, 8), "big")
    mask_key = _read_exact(sock, 4) if masked else b""
    payload = _read_exact(sock, length) if length else b""
    if masked:
        payload = bytes(b ^ mask_key[i % 4] for i, b in enumerate(payload))
    return opcode, payload


def iter_text_messages(sock: socket.socket, *, timeout_s: float, print_all: bool = False) -> Iterable[str]:
    """Yield incoming text messages until timeout or socket close."""
    deadline = time.time() + timeout_s

    while True:
        remaining = deadline - time.time()
        if remaining <= 0:
            return

        r, _, _ = select.select([sock], [], [], remaining)
        if not r:
            return

        opcode, payload = _recv_frame(sock)

        if opcode == 0x8:  # close
            return
        if opcode == 0x9:  # ping
            ws_send_pong(sock, payload)
            continue
        if opcode == 0xA:  # pong
            continue
        if opcode == 0x2:  # binary
            continue
        if opcode == 0x1:  # text
            msg = payload.decode("utf-8", errors="replace")
            if print_all:
                print(msg)
            yield msg
            continue
        continue


def cmd_send(args: argparse.Namespace) -> int:
    url = parse_ws_url(args.url)
    msg: str
    if args.message_file:
        msg = open(args.message_file, "r", encoding="utf-8").read()
    else:
        msg = args.message

    sock = ws_connect(url, timeout=args.connect_timeout, insecure_tls=args.insecure_tls)
    try:
        ws_send_text(sock, msg)
        # Best-effort drain a tiny bit (some servers only start sending after a command)
        for _ in iter_text_messages(sock, timeout_s=args.drain_timeout, print_all=args.print_all):
            pass
    finally:
        ws_send_close(sock)
        try:
            sock.close()
        except Exception:
            pass
    return 0


def cmd_wait(args: argparse.Namespace) -> int:
    url = parse_ws_url(args.url)
    wanted = [t.strip() for t in args.wait_tags.split(",") if t.strip()]
    if not wanted:
        raise WsError("--wait-tags must include at least one tag")

    sock = ws_connect(url, timeout=args.connect_timeout, insecure_tls=args.insecure_tls)
    try:
        for msg in iter_text_messages(sock, timeout_s=args.timeout, print_all=args.print_all):
            try:
                obj = json.loads(msg)
            except json.JSONDecodeError:
                continue
            tag = obj.get("tag")
            if tag in wanted:
                if args.print_match:
                    print(msg)
                return 0
    finally:
        ws_send_close(sock)
        try:
            sock.close()
        except Exception:
            pass

    print(f"Timed out waiting for tags: {wanted}", file=sys.stderr)
    return 2


def main() -> int:
    ap = argparse.ArgumentParser(prog="hydra_ws.py")
    sub = ap.add_subparsers(dest="cmd", required=True)

    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--url", required=True, help="ws://... or wss://... hydra-node API endpoint")
    common.add_argument("--connect-timeout", type=float, default=10.0)
    common.add_argument("--insecure-tls", action="store_true", help="Disable TLS verification for wss:// (dev only)")
    common.add_argument("--print-all", action="store_true", help="Print all incoming messages")

    sp_send = sub.add_parser("send", parents=[common], help="Send one text message and exit")
    group = sp_send.add_mutually_exclusive_group(required=True)
    group.add_argument("--message", help="Raw message to send (typically JSON)")
    group.add_argument("--message-file", help="Path to file containing the message to send")
    sp_send.add_argument("--drain-timeout", type=float, default=0.5, help="Seconds to read after sending (best-effort)")
    sp_send.set_defaults(func=cmd_send)

    sp_wait = sub.add_parser("wait", parents=[common], help="Wait for one of the given tags and exit")
    sp_wait.add_argument("--wait-tags", required=True, help="Comma-separated list of tag values to wait for")
    sp_wait.add_argument("--timeout", type=float, default=60.0)
    sp_wait.add_argument("--print-match", action="store_true", help="Print the matching JSON message")
    sp_wait.set_defaults(func=cmd_wait)

    args = ap.parse_args()
    try:
        return int(args.func(args))
    except WsError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
