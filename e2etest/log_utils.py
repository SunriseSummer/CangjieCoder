#!/usr/bin/env python3
"""
端到端测试日志记录与对比工具。

功能：
  - 每次测试运行后将完整 CLI 日志保存到 e2etest/<test_dir>/<YYYYMMDD_HHMMSS>.log
  - 对比当前日志与上一次日志，检查是否有明显退化
  - 提供 LoggingTestCase 基类，自动化日志保存与对比流程

日志目录结构：
  e2etest/
  ├── mock_agent/            # test_mock_agent.py 各用例的日志
  │   ├── 20260526_035000.log
  │   └── 20260526_040000.log
  ├── kimi_smoke/            # test_kimi_smoke.py 的日志
  │   ├── 20260526_035000.log
  │   └── ...
  └── ...
"""

from __future__ import annotations

import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional


E2ETEST_DIR = Path(__file__).resolve().parent


def get_log_dir(test_name: str) -> Path:
    """获取测试用例的日志目录，自动创建。"""
    log_dir = E2ETEST_DIR / test_name
    log_dir.mkdir(parents=True, exist_ok=True)
    return log_dir


def save_log(test_name: str, content: str) -> Path:
    """将日志内容保存到对应目录的时间戳文件中。

    返回保存的日志文件路径。
    """
    log_dir = get_log_dir(test_name)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    log_path = log_dir / f"{timestamp}.log"
    # 避免同一秒内重名
    counter = 1
    while log_path.exists():
        log_path = log_dir / f"{timestamp}_{counter}.log"
        counter += 1
    log_path.write_text(content, encoding="utf-8")
    return log_path


def find_previous_log(test_name: str, current_log: Path) -> Optional[Path]:
    """查找当前日志之前的最近一次日志文件。"""
    log_dir = get_log_dir(test_name)
    logs = sorted(
        [f for f in log_dir.glob("*.log") if f != current_log],
        key=lambda f: f.name,
    )
    return logs[-1] if logs else None


def _extract_duration(log: str) -> Optional[float]:
    """从日志头部提取耗时（秒），未找到返回 None。"""
    m = re.search(r"^耗时:\s*([\d.]+)s", log, re.MULTILINE)
    return float(m.group(1)) if m else None


def _extract_iterations(log: str) -> Optional[int]:
    """从日志头部提取迭代次数，未找到返回 None。"""
    m = re.search(r"^迭代次数:\s*(\d+)", log, re.MULTILINE)
    return int(m.group(1)) if m else None


def compare_logs(current: str, previous: str) -> tuple[list[str], list[str]]:
    """对比当前日志与上次日志，返回 (退化问题列表, 信息展示列表)。

    退化问题列表（issues）：疑似退化的项目，由调用方决定是否告警。
    信息展示列表（info）：耗时和迭代次数等变化，仅供展示参考，不判定退化。

    检查维度：
      1. 新增错误关键字
      2. 工具调用失败次数增加
      3. 最终结果状态变化（[final] 是否出现）
      4. 异常/崩溃信号
      5. 耗时变化（仅展示）
      6. 迭代次数变化（仅展示）
    """
    issues: list[str] = []
    info: list[str] = []

    # 错误关键字检查
    error_patterns = [
        r"ERROR:",
        r"FAILED",
        r"\bpanic\b",
        r"\bcrash\b",
        r"异常退出",
        r"timeout",
        r"超时",
        r"Invalid utf8",
    ]
    for pattern in error_patterns:
        cur_count = len(re.findall(pattern, current, re.IGNORECASE))
        prev_count = len(re.findall(pattern, previous, re.IGNORECASE))
        if cur_count > prev_count:
            issues.append(
                f"关键字 '{pattern}' 出现次数增加: {prev_count} → {cur_count}"
            )

    # [final] 标记检查
    cur_finals = current.count("[final]")
    prev_finals = previous.count("[final]")
    if cur_finals < prev_finals:
        issues.append(
            f"[final] 标记减少: {prev_finals} → {cur_finals}（可能有任务未完成）"
        )

    # 工具调用失败检查（使用 [tool-error] 前缀，这是实际工具失败的标记；
    # 不匹配 [tool-result] 内容中的"错误"等关键字，因为 AI 生成的
    # 任务描述可能包含这些词，导致误报）
    cur_tool_errors = len(re.findall(r"\[tool-error\]", current))
    prev_tool_errors = len(re.findall(r"\[tool-error\]", previous))
    if cur_tool_errors > prev_tool_errors:
        issues.append(
            f"工具调用失败次数增加: {prev_tool_errors} → {cur_tool_errors}"
        )

    # 重试次数检查
    cur_retries = current.count("sendWithRetry")
    prev_retries = previous.count("sendWithRetry")
    if cur_retries > prev_retries + 2:  # 容忍小幅波动
        issues.append(
            f"重试次数显著增加: {prev_retries} → {cur_retries}"
        )

    # 耗时对比（仅展示，不判定退化）
    cur_dur = _extract_duration(current)
    prev_dur = _extract_duration(previous)
    if cur_dur is not None and prev_dur is not None:
        delta = cur_dur - prev_dur
        sign = "+" if delta >= 0 else ""
        info.append(f"耗时: {prev_dur:.1f}s → {cur_dur:.1f}s ({sign}{delta:.1f}s)")
    elif cur_dur is not None:
        info.append(f"耗时: {cur_dur:.1f}s（上次无数据）")

    # 迭代次数对比（仅展示，不判定退化）
    cur_iter = _extract_iterations(current)
    prev_iter = _extract_iterations(previous)
    if cur_iter is not None and prev_iter is not None:
        delta = cur_iter - prev_iter
        sign = "+" if delta >= 0 else ""
        info.append(f"迭代次数: {prev_iter} → {cur_iter} ({sign}{delta})")
    elif cur_iter is not None:
        info.append(f"迭代次数: {cur_iter}（上次无数据）")

    return issues, info


def format_log_content(
    test_name: str,
    stdout: str,
    stderr: str,
    duration_secs: float,
    passed: bool,
    error_msg: str = "",
    iterations: Optional[int] = None,
) -> str:
    """格式化完整的测试日志内容。"""
    parts = [
        f"{'=' * 72}",
        f"测试用例: {test_name}",
        f"运行时间: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}",
        f"耗时: {duration_secs:.1f}s",
        f"结果: {'PASS' if passed else 'FAIL'}",
    ]
    if iterations is not None:
        parts.append(f"迭代次数: {iterations}")
    if error_msg:
        parts.append(f"错误信息: {error_msg}")
    parts.append(f"{'=' * 72}")
    parts.append("")
    parts.append("--- STDOUT ---")
    parts.append(stdout)
    if stderr.strip():
        parts.append("")
        parts.append("--- STDERR ---")
        parts.append(stderr)
    parts.append("")
    parts.append(f"{'=' * 72}")
    parts.append(f"END OF LOG: {test_name}")
    parts.append(f"{'=' * 72}")
    return "\n".join(parts)
