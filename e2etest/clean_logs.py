#!/usr/bin/env python3
"""
一键清理 e2etest 各子目录下的 *.log 日志文件。

用法：
    cd coder
    python3 e2etest/clean_logs.py          # 列出待清理的日志文件
    python3 e2etest/clean_logs.py --force   # 实际执行清理
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description="清理 e2etest 下所有 *.log 日志文件")
    parser.add_argument("--force", action="store_true",
                        help="实际执行删除；不加此参数时仅列出待删文件")
    args = parser.parse_args()

    e2etest_dir = Path(__file__).resolve().parent
    logs = sorted(e2etest_dir.rglob("*.log"))

    if not logs:
        print("没有找到任何 .log 文件。")
        return

    total_size = 0
    for log in logs:
        size = log.stat().st_size
        total_size += size
        rel = log.relative_to(e2etest_dir)
        if args.force:
            log.unlink()
            print(f"  已删除: {rel}  ({size:,} bytes)")
        else:
            print(f"  待删除: {rel}  ({size:,} bytes)")

    print(f"\n共 {len(logs)} 个日志文件，总大小 {total_size:,} bytes。")
    if not args.force:
        print("提示：加 --force 参数执行实际清理。")


if __name__ == "__main__":
    main()
