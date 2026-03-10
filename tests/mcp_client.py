"""MCP stdio client for testing CangjieCoder service.

Uses batch communication: all requests are collected, sent to the
service in one subprocess.communicate() call, and responses are parsed
after the service exits.  This avoids Cangjie runtime stdin buffering
issues with pipes (see issue.md for details).
"""

import io
import json
import os
import subprocess

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_BIN = os.path.join(REPO_ROOT, "target", "release", "bin", "cangjiecoder")
DEFAULT_WORKSPACE = os.path.join(REPO_ROOT, "tests", "cangjie")

# Shared library directories needed at runtime
_LIB_DIRS = [
    os.path.join(REPO_ROOT, "target", "release", "cjtreesitter"),
    os.path.join(REPO_ROOT, "cangjie-tree-sitter", "treesitter"),
]


def _encode_frame(body: str) -> bytes:
    """Encode a JSON body string into an MCP stdio frame."""
    body_bytes = body.encode("utf-8")
    header = f"Content-Length: {len(body_bytes)}\r\n\r\n"
    return header.encode("ascii") + body_bytes


def _parse_frames(data: bytes) -> list:
    """Parse multiple MCP frames from raw byte data."""
    results = []
    stream = io.BytesIO(data)
    while True:
        content_length = None
        while True:
            line = stream.readline()
            if not line:
                return results
            text = line.decode("utf-8", errors="replace").strip()
            if text.startswith("Content-Length:"):
                content_length = int(text.split(":", 1)[1].strip())
            if text == "":
                break
        if content_length is None:
            return results
        body = stream.read(content_length)
        if len(body) < content_length:
            return results
        results.append(json.loads(body.decode("utf-8")))
    return results


def _build_env():
    """Build environment with library paths for the service."""
    env = os.environ.copy()
    extra = [d for d in _LIB_DIRS if os.path.isdir(d)]
    stdx = env.get("STDX_PATH", "")
    if stdx and os.path.isdir(stdx):
        extra.append(stdx)
    if extra:
        existing = env.get("LD_LIBRARY_PATH", "")
        env["LD_LIBRARY_PATH"] = ":".join(
            extra + ([existing] if existing else [])
        )
    return env


class McpClient:
    """Batch MCP client: collects tool calls, executes in one session.

    Usage:
        client = McpClient()
        client.start()
        client.call_tool("workspace.read_file", {"path": "src/main.cj"})
        client.call_tool("workspace.list_files")
        results = client.execute()
        # results[0] = read_file result, results[1] = list_files result
    """

    def __init__(self, workspace=None, service_bin=None):
        self.workspace = workspace or os.environ.get(
            "WORKSPACE_PATH", DEFAULT_WORKSPACE
        )
        self.service_bin = service_bin or os.environ.get(
            "SERVICE_BIN", DEFAULT_BIN
        )
        self._env = _build_env()
        self._req_id = 0
        self._frames = b""
        self._result_count = 0

    def _ensure_binary(self):
        if not os.path.isfile(self.service_bin):
            raise FileNotFoundError(
                f"Service binary not found: {self.service_bin}\n"
                "Build the project first: cjpm build"
            )

    def start(self):
        """Begin a new batch session with MCP initialization."""
        self._ensure_binary()
        self._req_id = 0
        self._frames = b""
        self._result_count = 0
        # Initialize handshake
        self._req_id += 1
        init_msg = {
            "jsonrpc": "2.0", "id": self._req_id, "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05", "capabilities": {},
                "clientInfo": {"name": "test-client", "version": "0.1.0"},
            },
        }
        self._frames += _encode_frame(json.dumps(init_msg))
        notif = {"jsonrpc": "2.0", "method": "notifications/initialized"}
        self._frames += _encode_frame(json.dumps(notif))

    def call_tool(self, name, arguments=None):
        """Queue a tool call. Returns will be in execute() results."""
        self._req_id += 1
        params = {"name": name}
        if arguments is not None:
            params["arguments"] = arguments
        msg = {
            "jsonrpc": "2.0", "id": self._req_id,
            "method": "tools/call", "params": params,
        }
        self._frames += _encode_frame(json.dumps(msg))
        self._result_count += 1

    def list_tools(self):
        """Queue a tools/list request."""
        self._req_id += 1
        msg = {
            "jsonrpc": "2.0", "id": self._req_id,
            "method": "tools/list", "params": {},
        }
        self._frames += _encode_frame(json.dumps(msg))
        self._result_count += 1

    def execute(self):
        """Send all queued frames and return parsed results.

        Returns a list of tool results in order. The init response
        is consumed internally and not included.
        """
        cmd = [self.service_bin, "mcp-stdio", "--repo", self.workspace]
        proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=self._env,
        )
        stdout, _ = proc.communicate(input=self._frames, timeout=120)
        all_responses = _parse_frames(stdout)
        # First response is initialize — skip it
        tool_responses = all_responses[1:]
        results = []
        for resp in tool_responses:
            result = resp.get("result", {})
            content = result.get("content", [])
            if content and "text" in content[0]:
                results.append(json.loads(content[0]["text"]))
            elif "tools" in result:
                results.append(result)
            else:
                results.append(result)
        self._result_count = 0
        return results
