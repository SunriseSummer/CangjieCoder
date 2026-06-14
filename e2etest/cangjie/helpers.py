#!/usr/bin/env python3
"""
仓颉语言 AI Coding 端到端测试的共享工具。

功能：
  - 将 .github/skills 目录下的仓颉 Skills 拷贝到沙箱的 .agents/skills 目录
  - 提供统一的环境配置（通过框架层 provider/model 参数）
  - 提供仓颉项目初始化辅助

设计原则：
  Coder 本身不做仓颉语言专项定制，它只是一个通用 AI Coding Agent。
  仓颉语言的知识（语法、编译、项目结构等）全部来自 Skills 提供的文档。
  模型在 Skills 的帮助下编写代码，但通常不能一次写对，需要通过编译报错
  信息迭代修正，逐渐收敛到正确结果。

  服务商和模型通过 run_all.py 的 --provider/--model 参数指定，
  测试通过 coder 的 /connect 和 /model 命令完成端到端配置。
"""

from __future__ import annotations

import os
import shutil
from pathlib import Path

from ..driver import CoderProc, Sandbox, get_default_model


# 仓颉 Skills 来源目录（相对于仓库根目录）
SKILLS_SOURCE = Path(__file__).resolve().parent.parent.parent.parent / ".github" / "skills"


def copy_skills_to_sandbox(sb: Sandbox) -> None:
    """将 .github/skills 下的仓颉 Skills 拷贝到沙箱 .agents/skills 目录。"""
    target = sb.cwd / ".agents" / "skills"
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True, exist_ok=True)
    if not SKILLS_SOURCE.exists():
        raise FileNotFoundError(f"Skills source not found: {SKILLS_SOURCE}")
    for skill_dir in SKILLS_SOURCE.iterdir():
        if skill_dir.is_dir():
            shutil.copytree(skill_dir, target / skill_dir.name)


def create_cangjie_sandbox(provider: str = "kimi") -> Sandbox:
    """创建并配置好仓颉 Skills 和服务商引导配置的沙箱。

    注意：系统提示是通用的，不包含任何仓颉语言的专项知识。
    仓颉知识完全通过 .agents/skills 下的 Skills 注入。

    服务商和模型的最终配置由调用方通过 connect_provider() 完成。
    """
    sb = Sandbox.create()
    sb.write_bootstrap_config(
        provider=provider,
        system_prompt=(
            "你是一个严格遵守工具调用协议的 coding agent。"
            "涉及文件操作必须调用对应工具（write_file/edit_file/read_file），"
            "运行命令用 run_bash，搜索用 grep_search/glob_search。"
            "禁止把代码贴在回复正文里。"
        ),
    )
    copy_skills_to_sandbox(sb)
    return sb


def create_coder_proc(
    sb: Sandbox,
    startup_timeout: float = 30.0,
    provider: str = "kimi",
    model: str | None = None,
) -> CoderProc:
    """创建并启动 cangjiecoder 子进程，通过 /connect 和 /model 完成服务商配置。"""
    model = model or get_default_model(provider)
    cp = CoderProc(
        sb,
        startup_timeout=startup_timeout,
    )
    cp.connect_provider(provider, model)
    return cp


def write_cjpm_toml(cwd: Path, name: str, *, output_type: str = "executable") -> None:
    """在 cwd 写入最小的 cjpm.toml 配置文件。"""
    content = f"""[package]
  cjc-version = "1.0.5"
  name = "{name}"
  description = ""
  version = "1.0.0"
  output-type = "{output_type}"

[dependencies]
"""
    (cwd / "cjpm.toml").write_text(content, encoding="utf-8")


def cjpm_build(sb: Sandbox) -> tuple[bool, str]:
    """在沙箱中执行 cjpm build，返回 (成功与否, 合并输出)。"""
    return _run_cjpm(sb, "cjpm build")


def cjpm_run(sb: Sandbox) -> tuple[bool, str]:
    """在沙箱中执行 cjpm run，返回 (成功与否, 合并输出)。"""
    return _run_cjpm(sb, "cjpm run")


def cjpm_test(sb: Sandbox) -> tuple[bool, str]:
    """在沙箱中执行 cjpm build && cjpm test，返回 (成功与否, 合并输出)。"""
    return _run_cjpm(sb, "cjpm build && cjpm test")


def _run_cjpm(sb: Sandbox, cmd: str) -> tuple[bool, str]:
    import subprocess
    env = os.environ.copy()
    env["HOME"] = str(sb.root)
    result = subprocess.run(
        ["bash", "-c", cmd],
        cwd=str(sb.cwd),
        env=env,
        capture_output=True,
        text=True,
        timeout=180,
    )
    return result.returncode == 0, result.stdout + result.stderr


def read_data_file(data_dir: Path, name: str) -> str:
    """从测试用例 data 目录读取文件内容。"""
    path = data_dir / name
    return path.read_text(encoding="utf-8")


def run_scenarios(
    cases: list[tuple[str, callable]],
) -> tuple[bool, str, str, str]:
    """顺序运行多个测试场景，任一失败即停止。

    每个 case 是 (label, runner_func)，runner_func 返回标准四元组。
    """
    stdout_parts: list[str] = []
    stderr_parts: list[str] = []
    for label, runner in cases:
        passed, stdout, stderr, error_msg = runner()
        stdout_parts.append(f"=== {label} stdout ===\n{stdout}")
        stderr_parts.append(stderr)
        if not passed:
            return False, "\n\n".join(stdout_parts), "\n\n".join(stderr_parts), error_msg
    return True, "\n\n".join(stdout_parts), "\n\n".join(stderr_parts), ""
