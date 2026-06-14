#!/usr/bin/env python3
"""
端到端测试驱动：基于 Python 子进程 + pipe 驱动编译后的 cangjiecoder
二进制做真实交互测试。

之所以放在 Python 而不是 Cangjie 单元测试里：
 1. 在 cjpm test 环境中 spawn 抽取子进程 stdout/stderr 偶现死锁，难以排查；
 2. Python 的 subprocess + threading 模型成熟，社区方案稳定；
 3. 这层 e2e 测试只关心二进制的外部行为，与实现语言无关；
 4. 便于在 CI 与本地脚本中通过 `pytest` 一键运行，并把单测之外的回归
    问题快速暴露出来。

参考 OpenAI Codex / aider 项目的 black-box harness：
 - 启动一个本地 mock OpenAI 服务端（仅 stdlib，无第三方依赖）；
 - 把它的 endpoint 写进沙箱 HOME 的 config.json；
 - 启动 cangjiecoder 子进程；按脚本发送命令，等待预期输出；
 - 验证副作用（文件被创建/编辑、journal 命中等）。
"""

from __future__ import annotations

import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
from contextlib import contextmanager
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


# ---------------------------------------------------------------------------
# Windows 控制台 / 管道默认 GBK(cp936) 编码，输出 ▶/emoji/✓ 等字符会触发
# UnicodeEncodeError。将本进程的 stdout/stderr 重配置为 UTF-8（替换不可编码者），
# 确保测试运行器与实时回显在 Windows 上不崩溃。日志文件本身始终以 UTF-8 写入。
# ---------------------------------------------------------------------------
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[union-attr]
    except Exception:
        pass


# ---------------------------------------------------------------------------
# 服务商配置（仅 env var 映射 + 默认模型，端点由 coder 注册表管理）
# ---------------------------------------------------------------------------

PROVIDER_ENV_KEYS: dict[str, str] = {
    "huawei": "HUAWEI_API_KEY",
    "kimi": "KIMI_API_KEY",
    "zhipu": "ZHIPU_API_KEY",
    "deepseek": "DEEPSEEK_API_KEY",
}

PROVIDER_DEFAULT_MODELS: dict[str, str] = {
    "huawei": "kimi-k2.6",
    "kimi": "kimi-k2.6",
    "zhipu": "glm-5.1",
    "deepseek": "deepseek-v4-pro",
}


def get_api_key(provider: str) -> str:
    """从环境变量获取指定服务商的 API Key。"""
    env_key = PROVIDER_ENV_KEYS.get(provider, "")
    return os.environ.get(env_key, "") if env_key else ""


def get_default_model(provider: str) -> str:
    """获取指定服务商的默认模型。"""
    return PROVIDER_DEFAULT_MODELS.get(provider, "")


def collect_api_keys() -> dict[str, str]:
    """收集所有可用服务商的 API Key（从环境变量）。"""
    keys: dict[str, str] = {}
    for provider_id, env_key in PROVIDER_ENV_KEYS.items():
        val = os.environ.get(env_key, "")
        if val:
            keys[provider_id] = val
    return keys


# ---------------------------------------------------------------------------
# 二进制路径解析
# ---------------------------------------------------------------------------

def find_binary() -> Path:
    """返回 cangjiecoder 二进制的绝对路径。

    优先级：
     1. 环境变量 CANGJIECODER_BIN
     2. ../target/release/bin/main(.exe) 相对此脚本
    """
    env = os.environ.get("CANGJIECODER_BIN")
    if env and Path(env).exists():
        return Path(env)
    here = Path(__file__).resolve()
    bin_dir = here.parent.parent / "target" / "release" / "bin"
    # Windows 下二进制带 .exe 后缀
    name = "main.exe" if os.name == "nt" else "main"
    candidate = bin_dir / name
    if candidate.exists():
        return candidate
    raise FileNotFoundError(
        "cangjiecoder binary not found. Build with `cjpm build` first "
        "or set CANGJIECODER_BIN."
    )


def _windows_dll_dirs() -> list[str]:
    """Windows 专用：返回运行 main.exe 所需的运行时 / stdx 动态库目录。

    直接运行 ``target/release/bin/main.exe`` 会因找不到 Cangjie 运行时与 stdx
    的 DLL 而失败（0xC0000135）。``cjpm run`` 会自动注入这些搜索路径，但 e2e
    需要自定义 cwd 与 HOME 沙箱，无法走 cjpm，因此这里手动拼装：
     - ``$CANGJIE_HOME/runtime/lib/windows_x86_64_cjnative``、``/bin``、``/tools/bin``
     - 从 ``cjpm.toml`` 的 ``path-option`` 解析出的 stdx 动态库目录
    """
    dirs: list[str] = []
    cangjie_home = os.environ.get("CANGJIE_HOME", "")
    if cangjie_home:
        base = Path(cangjie_home)
        dirs.append(str(base / "runtime" / "lib" / "windows_x86_64_cjnative"))
        dirs.append(str(base / "bin"))
        dirs.append(str(base / "tools" / "bin"))
    toml = Path(__file__).resolve().parent.parent / "cjpm.toml"
    if toml.exists():
        text = toml.read_text(encoding="utf-8")
        project_root = toml.parent
        for group in re.findall(r"path-option\s*=\s*\[([^\]]*)\]", text):
            for p in re.findall(r'"([^"]+)"', group):
                # path-option 多为相对路径（如 ./stdx/dynamic/stdx）。子进程的 cwd
                # 是沙箱工作目录，相对 PATH 项会相对沙箱解析而失效，因此统一相对
                # 项目根目录解析为绝对路径。
                resolved = (project_root / p).resolve()
                dirs.append(str(resolved))
    return [d for d in dirs if d and Path(d).exists()]



# ---------------------------------------------------------------------------
# 沙箱 HOME 与 config.json
# ---------------------------------------------------------------------------

@dataclass
class Sandbox:
    """隔离 HOME 沙箱：每个测试用例独享，结束自动清理。"""
    root: Path
    cwd: Path
    config_path: Path

    @classmethod
    def create(cls) -> "Sandbox":
        root = Path(tempfile.mkdtemp(prefix="cangjiecoder_e2e_"))
        cfg_dir = root / ".agents" / "cangjiecoder"
        cfg_dir.mkdir(parents=True, exist_ok=True)
        cwd = root / "workdir"
        cwd.mkdir(parents=True, exist_ok=True)
        return cls(root=root, cwd=cwd, config_path=cfg_dir / "config.json")

    def write_config(
        self,
        endpoint: str,
        model: str,
        api_key: str,
        provider: str = "deepseek",
        system_prompt: str = "you are a coder.",
    ) -> None:
        body = {
            "currentProvider": provider,
            "currentModel": model,
            "systemPrompt": system_prompt,
            "credentials": {
                provider: {"apiKey": api_key, "endpoint": endpoint},
            },
        }
        self.config_path.write_text(json.dumps(body), encoding="utf-8")

    def write_bootstrap_config(
        self,
        provider: str,
        system_prompt: str = (
            "你是一个严格遵守工具调用协议的 coding agent。"
            "涉及文件操作必须调用对应工具（write_file/edit_file/read_file），"
            "运行命令用 run_bash。禁止把代码贴在回复正文里。"
        ),
    ) -> None:
        """写入引导配置：仅存储 API Key，端点由 coder 注册表管理。

        设置 ``currentProvider`` 为目标服务商，使 bootstrap 能直接通过。
        之后测试通过 ``/connect`` 和 ``/model`` 命令完成最终配置。
        """
        api_keys = collect_api_keys()
        api_key = api_keys.get(provider, "")
        if not api_key:
            raise ValueError(
                f"API key for provider '{provider}' not found. "
                f"Set {PROVIDER_ENV_KEYS.get(provider, '???')} env var."
            )
        # 存储所有可用的 API Key，方便 /connect 切换时直接确认
        credentials: dict[str, dict[str, str]] = {}
        for pid, key in api_keys.items():
            credentials[pid] = {"apiKey": key, "endpoint": ""}
        body = {
            "currentProvider": provider,
            "currentModel": "",
            "systemPrompt": system_prompt,
            "credentials": credentials,
        }
        self.config_path.write_text(json.dumps(body), encoding="utf-8")

    def cleanup(self) -> None:
        shutil.rmtree(self.root, ignore_errors=True)


# ---------------------------------------------------------------------------
# 子进程驱动
# ---------------------------------------------------------------------------

class CoderProc:
    """包装一个运行中的 cangjiecoder 子进程，提供同步 send/wait。

    特性：
      - 实时流式输出：当 ``echo=True`` (默认) 时，stdout / stderr 的每一段
        内容会被即时打印到当前进程的 sys.stdout / sys.stderr，方便 ``pytest -s``
        实时观测 Coder 迭代过程，而不必等到测试结束后才看到输出。
      - 全量缓存：所有 stdout / stderr 数据同时累积到内部缓冲区，供
        ``wait_for`` 和断言使用。
      - 单行发送：``send`` 会自动把内嵌换行替换为空格，避免 REPL 的
        ``readln()`` 把一条多行提示拆成多次独立的 agent 调用。
    """

    def __init__(self, sb: Sandbox, env_extra: dict[str, str] | None = None,
                 cli_args: list[str] | None = None,
                 startup_timeout: float = 15.0,
                 echo: bool = True) -> None:
        binary = find_binary()
        env = os.environ.copy()
        env["HOME"] = str(sb.root)
        # Windows 下 resolveHomeDir() 优先读取 USERPROFILE，需一并指向沙箱，
        # 否则会落到真实用户目录，破坏隔离。
        if os.name == "nt":
            env["USERPROFILE"] = str(sb.root)
            dll_dirs = _windows_dll_dirs()
            if dll_dirs:
                env["PATH"] = os.pathsep.join(dll_dirs) + os.pathsep + env.get("PATH", "")
        if env_extra:
            env.update(env_extra)
        self._echo = echo
        cmd = [str(binary)] + (cli_args or [])
        self._proc = subprocess.Popen(
            cmd,
            cwd=str(sb.cwd),
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,
        )
        self._stdout_buf: list[bytes] = []
        self._stderr_buf: list[bytes] = []
        self._lock = threading.Lock()
        self._t_out = threading.Thread(
            target=self._drain, args=(self._proc.stdout, self._stdout_buf, sys.stdout),
            daemon=True)
        self._t_err = threading.Thread(
            target=self._drain, args=(self._proc.stderr, self._stderr_buf, sys.stderr),
            daemon=True)
        self._t_out.start()
        self._t_err.start()
        if not self.wait_for("[user-input]", timeout=startup_timeout):
            self.close(timeout=2.0)
            raise RuntimeError(
                f"cangjiecoder did not show prompt within {startup_timeout}s. "
                f"stdout:\n{self.stdout()}\nstderr:\n{self.stderr()}"
            )

    def _drain(self, stream, buf: list[bytes], echo_target) -> None:
        """持续读取子进程输出流，同时缓存与实时回显。"""
        try:
            while True:
                chunk = stream.read(1024)
                if not chunk:
                    return
                with self._lock:
                    buf.append(chunk)
                if self._echo:
                    try:
                        text = chunk.decode("utf-8", errors="replace")
                        echo_target.write(text)
                        echo_target.flush()
                    except Exception:
                        pass
        except Exception:
            return

    def stdout(self) -> str:
        with self._lock:
            return b"".join(self._stdout_buf).decode("utf-8", errors="replace")

    def stderr(self) -> str:
        with self._lock:
            return b"".join(self._stderr_buf).decode("utf-8", errors="replace")

    def send(self, line: str) -> None:
        """发送一行文本到 Coder 的 stdin。

        自动将内嵌换行符 ``\\n`` 替换为空格，确保 REPL 的 ``readln()``
        将其作为一条完整消息处理，而不会拆成多条独立 agent 调用。
        """
        assert self._proc.stdin is not None
        # 合并为单行：REPL 按 readln() 逐行读取，内嵌 \n 会被拆成多条消息
        single_line = line.replace("\n", " ").strip()
        self._proc.stdin.write((single_line + "\n").encode("utf-8"))
        self._proc.stdin.flush()

    def stdout_pos(self) -> int:
        """返回当前 stdout 的字符长度，用于后续 wait 方法的 ``after`` 参数。"""
        return len(self.stdout())

    def wait_for(self, needle: str, timeout: float = 30.0, *, after: int = 0) -> bool:
        """等待 needle 出现在 stdout 中（``after`` 位置之后）。"""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if needle in self.stdout()[after:]:
                return True
            time.sleep(0.05)
        return False

    def wait_for_any(
        self, needles: list[str], timeout: float = 30.0, *, after: int = 0
    ) -> str | None:
        """等待任一 needle 出现在 stdout 的 ``after`` 位置之后，返回首先命中的
        needle；超时返回 None。

        配合 ``stdout_pos()`` 使用可避免重复匹配历史内容::

            pos = cp.stdout_pos()
            cp.send("some command")
            hit = cp.wait_for_any(["[final]"], after=pos)
        """
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            out = self.stdout()[after:]
            for n in needles:
                if n in out:
                    return n
            time.sleep(0.05)
        return None

    def count(self, needle: str, *, after: int = 0) -> int:
        """返回 needle 在 stdout 的 ``after`` 位置之后出现的次数。"""
        return self.stdout()[after:].count(needle)

    def close(self, timeout: float = 8.0) -> int:
        try:
            self.send("/exit")
        except Exception:
            pass
        try:
            return self._proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            self._proc.terminate()
            try:
                return self._proc.wait(timeout=3.0)
            except subprocess.TimeoutExpired:
                self._proc.kill()
                return self._proc.wait()

    def connect_provider(self, provider: str, model: str | None = None) -> None:
        """使用 /connect 和 /model 命令切换服务商和模型。

        适用于 bootstrap 配置中已存储目标服务商 API Key 的场景：
        /connect 发现已有 Key 后提示确认，发送空行即可。

        统一走 /connect：启动 banner 用 displayName 展示，无法据此判断
        provider id，且 /connect 是幂等的（已配置 Key 时回车确认即可）。
        """
        pos = self.stdout_pos()
        self.send(f"/connect {provider}")
        # 兼容两种提示：
        #   无 Key：  "请输入 X 的 API Key > "
        #   已有 Key："已设置 API Key，直接回车确认使用，或输入新 API Key 覆盖 > "
        hit = self.wait_for_any(
            ["API Key >", "已设置 API Key", "已切换到"],
            timeout=10.0,
            after=pos,
        )
        if hit and "API Key" in hit:
            # 回车确认既有 Key
            self.send("")
            self.wait_for("已切换到", timeout=10.0, after=pos)
        elif not hit:
            raise RuntimeError(
                f"/connect {provider} timed out.\n"
                f"stdout (tail): {self.stdout()[-2000:]}"
            )

        if model:
            pos2 = self.stdout_pos()
            self.send(f"/model {model}")
            # 如果模型已经是当前模型，/model 仍输出 "已切换到"
            ok = self.wait_for("已切换到", timeout=10.0, after=pos2)
            if not ok:
                # 模型可能已经是默认模型，不需要切换
                current = self.stdout()
                if f"{model}" in current:
                    return
                raise RuntimeError(
                    f"/model {model} timed out.\n"
                    f"stdout (tail): {self.stdout()[-2000:]}"
                )

    def dump_logs(self, stdout_tail: int = 5000, stderr_tail: int = 2000) -> str:
        """返回格式化的日志摘要，用于测试失败时的诊断输出。"""
        out = self.stdout()
        err = self.stderr()
        parts = []
        parts.append(f"=== STDOUT (last {stdout_tail} chars) ===")
        parts.append(out[-stdout_tail:] if len(out) > stdout_tail else out)
        if err.strip():
            parts.append(f"\n=== STDERR (last {stderr_tail} chars) ===")
            parts.append(err[-stderr_tail:] if len(err) > stderr_tail else err)
        return "\n".join(parts)


# ---------------------------------------------------------------------------
# Mock OpenAI server
# ---------------------------------------------------------------------------

@dataclass
class ScriptedReply:
    """脚本化的一次模型响应。"""
    content: str = ""
    # [(id, name, args_json_str), ...]
    tool_calls: list = field(default_factory=list)
    finish_reason: str = "stop"

    def to_choice(self) -> dict:
        message: dict = {"role": "assistant", "content": self.content}
        if self.tool_calls:
            message["tool_calls"] = [
                {
                    "id": cid,
                    "type": "function",
                    "function": {"name": name, "arguments": args},
                }
                for cid, name, args in self.tool_calls
            ]
            message["content"] = self.content or None
        return {"index": 0, "message": message, "finish_reason": self.finish_reason}


class MockServer:
    """单线程 mock OpenAI Chat Completions 服务端。

    用法::

        ms = MockServer()
        ms.enqueue(ScriptedReply(content="..."))
        ms.start()
        ... # 测试代码访问 ms.endpoint()
        ms.stop()
    """

    def __init__(self) -> None:
        self._scripts: list = []
        self.requests: list = []
        self._server = None
        self._thread = None
        self._lock = threading.Lock()
        self.port = 0

    def enqueue(self, reply: ScriptedReply) -> "MockServer":
        self._scripts.append(reply)
        return self

    def start(self) -> None:
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args, **kwargs):  # 静音
                pass

            def do_POST(self):
                length = int(self.headers.get("Content-Length", 0))
                raw = self.rfile.read(length)
                body = json.loads(raw.decode("utf-8")) if raw else {}
                with outer._lock:
                    outer.requests.append(body)
                    reply = outer._scripts.pop(0) if outer._scripts else ScriptedReply(
                        content="(默认 mock 回复)")
                resp = {
                    "id": "mock-1",
                    "object": "chat.completion",
                    "model": body.get("model", "mock"),
                    "choices": [reply.to_choice()],
                    "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15},
                }
                data = json.dumps(resp).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        sock = socket.socket()
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
        sock.close()
        self._server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
        self._thread.start()
        self.port = port

    def stop(self) -> None:
        if self._server:
            self._server.shutdown()
            self._server.server_close()
        if self._thread:
            self._thread.join(timeout=2.0)

    def endpoint(self) -> str:
        return f"http://127.0.0.1:{self.port}/v1/chat/completions"


@contextmanager
def mock_server():
    ms = MockServer()
    ms.start()
    try:
        yield ms
    finally:
        ms.stop()


@contextmanager
def sandbox():
    sb = Sandbox.create()
    try:
        yield sb
    finally:
        sb.cleanup()
