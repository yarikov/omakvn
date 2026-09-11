#!/usr/bin/env python3
"""Bound and safely re-encode kvn daemon NDJSON for the QML widget."""

from __future__ import annotations

import json
import selectors
import socket
import sys


MAX_LINE_BYTES = 16 * 1024 * 1024
READ_SIZE = 64 * 1024
MAX_NESTING_DEPTH = 64


class LineFramer:
    def __init__(self, max_line_bytes: int = MAX_LINE_BYTES) -> None:
        self.max_line_bytes = max_line_bytes
        self.buffer = bytearray()
        self.discarding = False

    def feed(self, chunk: bytes) -> list[bytes]:
        lines: list[bytes] = []
        offset = 0
        while offset < len(chunk):
            newline = chunk.find(b"\n", offset)
            end = len(chunk) if newline == -1 else newline
            fragment = chunk[offset:end]

            if not self.discarding:
                if len(self.buffer) + len(fragment) <= self.max_line_bytes:
                    self.buffer.extend(fragment)
                else:
                    self.buffer.clear()
                    self.discarding = True

            if newline == -1:
                break

            if not self.discarding and self.buffer:
                if self.buffer.endswith(b"\r"):
                    self.buffer.pop()
                if self.buffer:
                    lines.append(bytes(self.buffer))

            self.buffer.clear()
            self.discarding = False
            offset = newline + 1

        return lines


def nesting_is_bounded(line: bytes) -> bool:
    depth = 0
    in_string = False
    escaped = False
    for byte in line:
        if in_string:
            if escaped:
                escaped = False
            elif byte == ord("\\"):
                escaped = True
            elif byte == ord('"'):
                in_string = False
        elif byte == ord('"'):
            in_string = True
        elif byte in (ord("["), ord("{")):
            depth += 1
            if depth > MAX_NESTING_DEPTH:
                return False
        elif byte in (ord("]"), ord("}")):
            depth -= 1
    return True


def normalize_line(line: bytes) -> bytes | None:
    if not nesting_is_bounded(line):
        return None
    try:
        value = json.loads(line.decode("utf-8"))
        encoded = json.dumps(value, ensure_ascii=True, separators=(",", ":")).encode("ascii")
    except (UnicodeDecodeError, ValueError, RecursionError):
        return None
    return encoded if len(encoded) <= MAX_LINE_BYTES else None


def run(socket_path: str) -> int:
    daemon = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    daemon.connect(socket_path)
    daemon.sendall(b'{"cmd":"Attach"}\n')

    selector = selectors.DefaultSelector()
    selector.register(daemon, selectors.EVENT_READ, "daemon")
    selector.register(sys.stdin.buffer, selectors.EVENT_READ, "stdin")
    framer = LineFramer()

    while True:
        for key, _ in selector.select():
            if key.data == "daemon":
                chunk = daemon.recv(READ_SIZE)
                if not chunk:
                    return 0
                for line in framer.feed(chunk):
                    normalized = normalize_line(line)
                    if normalized is not None:
                        sys.stdout.buffer.write(normalized + b"\n")
                        sys.stdout.buffer.flush()
            else:
                command = sys.stdin.buffer.read1(READ_SIZE)
                if not command:
                    return 0
                daemon.sendall(command)


def main() -> int:
    if len(sys.argv) != 2:
        return 2
    try:
        return run(sys.argv[1])
    except (BrokenPipeError, ConnectionError, OSError):
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
