#!/usr/bin/env python3
"""端到端测试: 模拟 AI Agent 通过 MCP 工具开发 TaskManager 项目。

本测试侧重于 **AST 编辑、LSP 工具和高级 Skill 查询** 的覆盖，
与 e2etest_jsonparser 的编译迭代场景互补。

AI Agent 从零搭建一个仓颉任务管理器项目，流程中刻意引入常见的
AI 编码错误（缺少 import、缺少 @Derive 注解），然后通过
MCP 工具链发现并修复这些问题。

代码片段按迭代顺序编号存储在 ``codepieceN.ai`` 文件中:

  codepiece1.ai  cjpm.toml 项目配置
  codepiece2.ai  types.cj  优先级/状态枚举（首次, 缺少 @Derive[Equatable]）
  codepiece3.ai  task.cj   任务实体和存储管理
  codepiece4.ai  main.cj   主入口（首次, 缺少 import std.convert.*）
  codepiece5.ai  main.cj   修复版（补充 import std.convert.*）
  codepiece6.ai  task_test.cj  单元测试
  codepiece7.ai  summary() 函数的 AST 编辑替换体（增加标签显示）

开发流程共 8 个阶段:
  1. 搜索 Skill — 使用 batch_search 和 prompt_context
  2. 创建项目结构 — 逐步生成代码文件（含故意缺陷）
  3. AST 深度分析 — summary / parse / list / query / query_with_text
  4. AST 编辑 — 用 edit_ast_node 替换函数 → 验证 → 回滚
  5. 内容验证 — 读取文件、搜索文本
  6. 编译迭代 — 首次编译失败 → 分析 → 修复 → 重编译成功
  7. 测试迭代 — 首次测试失败 → 分析 → replace_text 修复 → 重测试
  8. LSP 工具 — status / probe / document_symbols / workspace_symbols / definition

覆盖的 MCP 工具 (20 个):
  skills.batch_search, skills.prompt_context, skills.search,
  workspace.set_root, workspace.create_file (含 overwrite),
  workspace.list_files, workspace.read_file, workspace.search_text,
  workspace.replace_text, workspace.rollback,
  workspace.run_build, workspace.run_test,
  cangjie.ast_summary, cangjie.ast_parse, cangjie.ast_list_nodes,
  cangjie.ast_query_nodes, cangjie.ast_query_nodes_with_text,
  cangjie.edit_ast_node,
  cangjie.lsp_status, cangjie.lsp_document_symbols

Usage:
    python tests/e2etest_taskmanager/run.py [--bin PATH] [--keep]
"""

import argparse
import os
import shutil
import sys
import tempfile

# ---------------------------------------------------------------------------
# 初始化 — 定位辅助模块和共享 MCP 客户端
# ---------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TESTS_DIR = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, TESTS_DIR)
from mcp_client import McpClient  # noqa: E402

REPO_ROOT = os.path.dirname(TESTS_DIR)
DEFAULT_BIN = os.path.join(REPO_ROOT, "target", "release", "bin", "cangjiecoder")


# ---------------------------------------------------------------------------
# 模拟 AI 模型请求 / Agent 推理过程
# ---------------------------------------------------------------------------

def ai_generate(piece_id, prompt=""):
    """模拟向 AI 模型发送请求，读取预存的代码片段。

    真实场景中会调用 LLM API。这里从 ``codepieceN.ai`` 读取，
    保证测试确定性。

    Args:
        piece_id: 片段编号，映射到 ``codepiece<id>.ai``。
        prompt:   模拟提示词（仅日志）。
    """
    path = os.path.join(SCRIPT_DIR, f"codepiece{piece_id}.ai")
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    label = os.path.basename(path)
    print(f"  🤖 AI 模型响应 ← {label}  ({len(content)} 字节)")
    if prompt:
        display = prompt[:80] + ('…' if len(prompt) > 80 else '')
        print(f"     提示词: {display}")
    return content


def agent_plan(title, details):
    """模拟 Agent 规划推理 — 思维链 (Chain-of-Thought)。"""
    print(f"\n  📋 Agent 规划: {title}")
    for line in details:
        print(f"     • {line}")


def agent_analyse(summary):
    """模拟 Agent 分析工具返回结果。"""
    print(f"  🔍 Agent 分析: {summary}")


def agent_decide(decision):
    """模拟 Agent 做出行动决策。"""
    print(f"  💡 Agent 决策: {decision}")


# ---------------------------------------------------------------------------
# 测试编排辅助
# ---------------------------------------------------------------------------

def step(msg):
    """打印阶段横幅。"""
    print(f"\n{'─' * 64}")
    print(f"  🔧  {msg}")
    print(f"{'─' * 64}")


# ---------------------------------------------------------------------------
# 主 e2e 场景
# ---------------------------------------------------------------------------

def run_e2e(service_bin, keep_workspace):
    """执行 TaskManager 项目开发全流程。

    模拟 AI Agent 从零搭建仓颉任务管理器，覆盖 AST 编辑、
    LSP 工具和编译迭代修复等场景。
    """

    workspace = tempfile.mkdtemp(prefix="cjcoder_e2e_taskmanager_")
    print(f"\n  工作区: {workspace}")

    passed = 0
    failed = 0
    errors = []

    def record(ok, name, detail=""):
        """记录检查点通过/失败。"""
        nonlocal passed, failed
        if ok:
            print(f"  ✓ {name}")
            passed += 1
        else:
            info = f": {detail}" if detail else ""
            print(f"  ✗ {name}{info}")
            failed += 1
            errors.append(name)

    def client():
        """创建新的 MCP 客户端会话。"""
        return McpClient(workspace=workspace, service_bin=service_bin)

    try:
        # ==============================================================
        # 阶段 1 — Skill 搜索: batch_search + prompt_context
        # 使用高级 Skill 工具收集仓颉语言参考资料
        # ==============================================================
        step("阶段 1: 使用高级 Skill 工具收集领域知识")

        agent_plan("批量搜索仓颉知识", [
            "使用 skills.batch_search 一次搜索多个主题",
            "使用 skills.prompt_context 生成 AI 可用的上下文",
            "使用 skills.search 补充搜索 class 相关知识",
        ])

        # --- 1a: 批量搜索 ---
        c = client()
        c.start()
        c.call_tool("skills.batch_search", {                                # 0
            "queries": ["enum 枚举 Derive", "class 类 构造", "单元测试 unittest"]
        })
        c.call_tool("skills.prompt_context", {                              # 1
            "query": "class 属性 方法",
            "limit": 2
        })
        c.call_tool("skills.search", {"query": "集合 ArrayList"})           # 2
        resp = c.execute()

        # 验证 batch_search 返回了 3 个查询的结果
        batch_ok = resp[0].get("ok") is True
        batch_count = resp[0].get("data", {}).get("queryCount", 0)
        record(batch_ok and batch_count == 3,
               f"skills.batch_search: {batch_count} 个查询结果")

        # 验证 prompt_context 返回了非空上下文
        ctx_ok = resp[1].get("ok") is True
        ctx_content = resp[1].get("data", {}).get("context", "")
        record(ctx_ok and len(ctx_content) > 0,
               f"skills.prompt_context: 返回 {len(ctx_content)} 字节上下文")

        # 验证普通搜索也正常工作
        record(resp[2].get("ok") is True, "skills.search(集合)")

        agent_analyse(
            "Skill 搜索完成。batch_search 高效获取了多个主题的参考资料，"
            "prompt_context 生成了可直接嵌入系统提示词的上下文块。"
        )

        # ==============================================================
        # 阶段 2 — 项目搭建: 创建文件（含故意缺陷）
        # ==============================================================
        step("阶段 2: 创建项目结构，生成源码文件（首次尝试）")

        agent_plan("项目架构设计", [
            "创建 cjpm.toml (可执行项目，SDK 1.0.5)",
            "生成 types.cj: 优先级/状态枚举（注意: 首次可能遗漏 @Derive）",
            "生成 task.cj: 任务实体和存储管理器",
            "生成 main.cj: 入口函数（注意: 可能遗漏 import std.convert.*）",
        ])

        # --- 2a: cjpm.toml ---
        cjpm_toml = ai_generate(1, "生成 cjpm.toml: 可执行项目 taskmanager")

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {
            "path": "cjpm.toml", "content": cjpm_toml
        })
        resp = c.execute()
        record(resp[1].get("ok") is True, "create_file(cjpm.toml)")

        # --- 2b: types.cj (缺少 @Derive[Equatable]) ---
        types_cj = ai_generate(
            2, "生成枚举: Priority(Low/Medium/High/Critical) + TaskStatus"
        )

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {
            "path": "src/types.cj", "content": types_cj
        })
        resp = c.execute()
        record(resp[1].get("ok") is True, "create_file(types.cj)")

        # --- 2c: task.cj ---
        task_cj = ai_generate(
            3, "生成 Task 类、TaskStats 结构体、TaskStore 管理器"
        )

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {
            "path": "src/task.cj", "content": task_cj
        })
        resp = c.execute()
        record(resp[1].get("ok") is True, "create_file(task.cj)")

        # --- 2d: main.cj (缺少 import std.convert.*) ---
        main_cj = ai_generate(
            4, "生成 main 入口: 演示任务增删改查、搜索、统计"
        )

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {
            "path": "src/main.cj", "content": main_cj
        })
        resp = c.execute()
        record(resp[1].get("ok") is True, "create_file(main.cj)")

        agent_analyse("项目文件创建完成。代码可能有遗漏，先做 AST 结构分析。")

        # --- 2e: 确认文件列表 ---
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.list_files", {"path": "src"})
        resp = c.execute()

        files_ok = resp[1].get("ok") is True
        file_count = resp[1].get("data", {}).get("count", 0) if files_ok else 0
        record(files_ok and file_count >= 3,
               f"list_files(src): {file_count} 个文件")

        # ==============================================================
        # 阶段 3 — AST 深度分析: 全面使用 AST 工具链
        # summary / parse / list_nodes / query_nodes / query_with_text
        # ==============================================================
        step("阶段 3: AST 深度分析 — 多工具协同审查代码结构")

        agent_plan("AST 多维度分析", [
            "ast_summary: 获取每个文件的顶层定义摘要（快速概览）",
            "ast_parse: 获取 main.cj 的完整 S-expression AST",
            "ast_list_nodes: 列出 task.cj 前 3 层的所有命名节点",
            "ast_query_nodes: 统计 types.cj 中的枚举定义数量",
            "ast_query_nodes_with_text: 提取 task.cj 中所有函数的源码",
        ])

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        # ast_summary — 各文件顶层定义
        c.call_tool("cangjie.ast_summary", {"path": "src/types.cj"})          # 1
        c.call_tool("cangjie.ast_summary", {"path": "src/task.cj"})           # 2
        # ast_parse — 完整 AST
        c.call_tool("cangjie.ast_parse", {"path": "src/main.cj"})             # 3
        # ast_list_nodes — 列出节点树
        c.call_tool("cangjie.ast_list_nodes", {                                # 4
            "path": "src/task.cj", "maxDepth": 3
        })
        # ast_query_nodes — 统计枚举定义
        c.call_tool("cangjie.ast_query_nodes", {                               # 5
            "path": "src/types.cj", "nodeType": "enumDefinition"
        })
        # ast_query_nodes_with_text — 提取函数源码
        c.call_tool("cangjie.ast_query_nodes_with_text", {                     # 6
            "path": "src/task.cj", "nodeType": "functionDefinition"
        })
        resp = c.execute()

        # 验证 ast_summary — types.cj 应包含枚举和函数定义
        types_entries = resp[1].get("data", {}).get("entries", [])
        record(resp[1].get("ok") is True and len(types_entries) > 0,
               f"ast_summary(types.cj): {len(types_entries)} 个顶层定义")

        # 验证 ast_summary — task.cj 应包含 class 和 struct 定义
        task_entries = resp[2].get("data", {}).get("entries", [])
        record(resp[2].get("ok") is True and len(task_entries) > 0,
               f"ast_summary(task.cj): {len(task_entries)} 个顶层定义")

        # 验证 ast_parse — main.cj 应有 mainDefinition
        main_sexp = resp[3].get("data", {}).get("sexp", "")
        record(resp[3].get("ok") is True and "mainDefinition" in main_sexp,
               "ast_parse(main.cj): 包含 mainDefinition")

        # 验证 ast_list_nodes — 返回节点列表
        list_ok = resp[4].get("ok") is True
        list_data = resp[4].get("data", {})
        record(list_ok and list_data.get("nodeCount", 0) > 0,
               f"ast_list_nodes(task.cj): {list_data.get('nodeCount', 0)} 个节点")

        # 验证 ast_query_nodes — types.cj 应有 2 个枚举定义
        enum_count = resp[5].get("data", {}).get("matchCount", 0)
        record(resp[5].get("ok") is True and enum_count >= 2,
               f"ast_query_nodes(enumDefinition): {enum_count} 个枚举")

        # 验证 ast_query_nodes_with_text — 提取函数体
        func_count = resp[6].get("data", {}).get("matchCount", 0)
        func_nodes = resp[6].get("data", {}).get("nodes", [])
        has_text = all("text" in n and len(n["text"]) > 0 for n in func_nodes)
        record(resp[6].get("ok") is True and func_count > 0 and has_text,
               f"ast_query_nodes_with_text(func): {func_count} 个函数含源码")

        agent_analyse(
            f"AST 分析完成: types.cj 有 {len(types_entries)} 个定义/{enum_count} 个枚举, "
            f"task.cj 有 {len(task_entries)} 个定义/{func_count} 个函数。"
            "\n     语法结构正确，但语义错误需要编译器发现。"
        )

        # ==============================================================
        # 阶段 4 — AST 编辑: edit_ast_node 替换函数 → 验证 → 回滚
        # 这是本测试的核心亮点: 演示 AST 级别的精确代码编辑
        # ==============================================================
        step("阶段 4: AST 编辑 — 精确替换函数定义并回滚")

        agent_plan("AST 编辑实验", [
            "用 ast_query_nodes_with_text 找到 summary() 函数",
            "用 edit_ast_node 替换 summary() 为增强版（含标签显示）",
            "读取文件验证替换结果",
            "用 workspace.rollback 恢复原始版本",
            "再次读取文件确认恢复成功",
        ])

        # --- 4a: 先找到 summary() 是第几个函数 ---
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("cangjie.ast_query_nodes_with_text", {                     # 1
            "path": "src/task.cj", "nodeType": "functionDefinition"
        })
        resp = c.execute()

        # 找到 summary() 函数的索引
        funcs = resp[1].get("data", {}).get("nodes", [])
        summary_idx = -1
        for i, node in enumerate(funcs):
            if "summary" in node.get("text", ""):
                summary_idx = i
                break
        record(summary_idx >= 0,
               f"找到 summary() 函数 (索引={summary_idx})")

        agent_analyse(f"summary() 是第 {summary_idx} 个函数定义节点。")

        # --- 4b: 执行 AST 编辑 → 验证 → 回滚, 全部在同一会话中完成 ---
        # 注意: 备份和回滚是会话级别状态，必须在同一个 MCP 会话中完成
        replacement = ai_generate(
            7, "生成 summary() 的增强版: 在摘要中包含标签列表"
        )

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        # 先读取原始内容用于后续比较
        c.call_tool("workspace.read_file", {"path": "src/task.cj"})            # 1
        # 执行 AST 编辑: 替换第 summary_idx 个函数定义
        c.call_tool("cangjie.edit_ast_node", {                                 # 2
            "path": "src/task.cj",
            "nodeType": "functionDefinition",
            "replacement": replacement,
            "index": summary_idx
        })
        # 读取编辑后的文件
        c.call_tool("workspace.read_file", {"path": "src/task.cj"})            # 3
        # 在同一会话中回滚
        c.call_tool("workspace.rollback")                                      # 4
        # 读取回滚后的文件
        c.call_tool("workspace.read_file", {"path": "src/task.cj"})            # 5
        resp = c.execute()

        original_task = resp[1].get("data", {}).get("content", "")
        edit_ok = resp[2].get("ok") is True
        edited_task = resp[3].get("data", {}).get("content", "")
        rollback_ok = resp[4].get("ok") is True
        restored_task = resp[5].get("data", {}).get("content", "")

        record(edit_ok, "edit_ast_node: 替换函数定义成功")

        # 验证替换后的文件包含新内容
        has_new_content = "tagStr" in edited_task or "parts" in edited_task
        record(has_new_content,
               "验证 AST 编辑: 新代码包含标签处理逻辑")

        agent_analyse("AST 编辑成功: summary() 已被替换为含标签显示的增强版本。")

        # --- 4c: 验证回滚结果 ---
        agent_decide("实验完成，回滚 AST 编辑以恢复原始代码。")

        record(rollback_ok, "workspace.rollback: 回滚成功")
        record(restored_task == original_task,
               "验证回滚: 文件内容与原始一致")

        agent_analyse("回滚成功: task.cj 已恢复到 AST 编辑前的状态。"
                      "\n     edit_ast_node + rollback 形成了安全的「实验→撤销」工作流。")

        # ==============================================================
        # 阶段 5 — 内容验证: 读取、搜索
        # ==============================================================
        step("阶段 5: 读取文件并验证内容")

        agent_plan("内容交叉验证", [
            "读取 cjpm.toml 确认项目名",
            "读取 types.cj 确认枚举定义",
            "全局搜索 TaskStore 确认引用",
        ])

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.read_file", {"path": "cjpm.toml"})             # 1
        c.call_tool("workspace.read_file", {"path": "src/types.cj"})          # 2
        c.call_tool("workspace.search_text", {"query": "TaskStore"})           # 3
        resp = c.execute()

        toml_content = resp[1].get("data", {}).get("content", "")
        record('name = "taskmanager"' in toml_content,
               "cjpm.toml 包含正确的包名")

        types_content = resp[2].get("data", {}).get("content", "")
        record("enum Priority" in types_content and "enum TaskStatus" in types_content,
               "types.cj 包含 Priority 和 TaskStatus 枚举")

        store_refs = resp[3].get("data", {}).get("count", 0)
        record(resp[3].get("ok") is True and store_refs >= 2,
               f"search_text(TaskStore): {store_refs} 处引用")

        agent_analyse("内容验证通过。准备首次编译。")

        # ==============================================================
        # 阶段 6 — 编译迭代: 首次编译失败 → 修复 → 重编译
        # main.cj 缺少 import std.convert.* 导致 Int64.parse() 报错
        # ==============================================================
        step("阶段 6: 编译项目 — 迭代修复 import 错误")

        agent_plan("首次编译尝试", [
            "执行 workspace.run_build",
            "预期: 编译失败（缺少 import std.convert.*）",
            "修复后重新编译",
        ])

        # --- 6a: 首次编译 → 预期失败 ---
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.run_build")                                     # 1
        resp = c.execute()

        build1 = resp[1]
        build1_exit = build1.get("data", {}).get("exitCode", -1)
        build1_stderr = build1.get("data", {}).get("stderr", "")
        build1_stdout = build1.get("data", {}).get("stdout", "")
        build1_output = build1_stderr + build1_stdout

        record(build1_exit != 0 and ("parse" in build1_output.lower()
               or "convert" in build1_output.lower()
               or "undeclared" in build1_output.lower()),
               "首次编译失败（预期: 缺少 import std.convert.*）")

        agent_analyse(
            f"编译失败 (exit={build1_exit})。"
            "\n     错误指向 Int64.parse() 调用 — 缺少 import std.convert.*。"
            f"\n     错误摘要: {build1_output[:200]}"
        )

        # --- 6b: AI 重新生成修复版 main.cj ---
        agent_decide("请求 AI 重新生成 main.cj，补充 import std.convert.*。")

        fixed_main = ai_generate(
            5, "修复 main.cj: 添加 import std.convert.* 以支持 Int64.parse()"
        )

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {                                 # 1
            "path": "src/main.cj",
            "content": fixed_main,
            "overwrite": True
        })
        resp = c.execute()
        record(resp[1].get("ok") is True,
               "create_file(main.cj, overwrite) 覆盖写入修复版")

        # --- 6c: 重新编译 → 预期成功 ---
        agent_plan("重新编译", ["import 修复后再次编译"])

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.run_build")                                     # 1
        resp = c.execute()

        build2 = resp[1]
        build2_exit = build2.get("data", {}).get("exitCode", -1)
        if build2_exit == 0:
            record(True, "重新编译成功 ✅")
            agent_analyse("编译通过！准备添加测试。")
        else:
            build2_stderr = build2.get("data", {}).get("stderr", "")
            record(False, "重新编译",
                   f"exit={build2_exit}, stderr={build2_stderr[:300]}")

        # ==============================================================
        # 阶段 7 — 测试迭代: 测试编译失败 → replace_text 修复 → 通过
        # types.cj 的枚举缺少 @Derive[Equatable]，
        # 测试中的 == 比较会编译报错
        # ==============================================================
        step("阶段 7: 生成测试 — 迭代修复 @Derive 注解")

        agent_plan("编写并运行测试", [
            "生成覆盖所有功能的单元测试",
            "首次运行预期失败: 枚举缺少 @Derive[Equatable]",
            "用 replace_text 精确插入注解",
            "重新运行测试",
        ])

        # --- 7a: 生成测试文件并首次运行 ---
        test_cj = ai_generate(
            6, "生成 TaskManager 完整测试: 覆盖创建/完成/取消/标签/搜索/统计"
        )

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {                                 # 1
            "path": "src/task_test.cj", "content": test_cj
        })
        c.call_tool("workspace.run_test")                                      # 2
        resp = c.execute()

        record(resp[1].get("ok") is True, "create_file(task_test.cj)")

        test1 = resp[2]
        test1_exit = test1.get("data", {}).get("exitCode", -1)
        test1_stderr = test1.get("data", {}).get("stderr", "")
        test1_stdout = test1.get("data", {}).get("stdout", "")
        test1_output = test1_stderr + test1_stdout

        record(test1_exit != 0 and ("==" in test1_output
               or "operator" in test1_output.lower()
               or "equatable" in test1_output.lower()
               or "deriving" in test1_output.lower()),
               "首次测试编译失败（预期: 枚举缺少 @Derive[Equatable]）")

        agent_analyse(
            f"测试编译失败 (exit={test1_exit})。"
            "\n     原因: Priority 和 TaskStatus 枚举未添加 @Derive[Equatable]。"
            "\n     仓颉需要显式标注 @Derive[Equatable] 才能对枚举使用 == 比较。"
        )

        # --- 7b: 用 replace_text 为两个枚举添加 @Derive[Equatable] ---
        agent_decide(
            "用 workspace.replace_text 为 Priority 和 TaskStatus 枚举"
            "各添加 @Derive[Equatable] 注解。"
        )

        # 修复 Priority 枚举
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.replace_text", {                                # 1
            "path": "src/types.cj",
            "oldText": "public enum Priority {",
            "newText": "@Derive[Equatable]\npublic enum Priority {"
        })
        resp = c.execute()
        record(resp[1].get("ok") is True,
               "replace_text: Priority 添加 @Derive[Equatable]")

        # 修复 TaskStatus 枚举
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.replace_text", {                                # 1
            "path": "src/types.cj",
            "oldText": "public enum TaskStatus {",
            "newText": "@Derive[Equatable]\npublic enum TaskStatus {"
        })
        resp = c.execute()
        record(resp[1].get("ok") is True,
               "replace_text: TaskStatus 添加 @Derive[Equatable]")

        # 同时需要添加 import std.deriving.* （@Derive 宏需要此导入）
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.replace_text", {                                # 1
            "path": "src/types.cj",
            "oldText": "package taskmanager",
            "newText": "package taskmanager\n\nimport std.deriving.*"
        })
        resp = c.execute()
        record(resp[1].get("ok") is True,
               "replace_text: 添加 import std.deriving.*")

        # --- 7c: 验证修复 ---
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.read_file", {"path": "src/types.cj"})          # 1
        resp = c.execute()

        fixed_types = resp[1].get("data", {}).get("content", "")
        record("@Derive[Equatable]" in fixed_types
               and "import std.deriving" in fixed_types,
               "验证修复: types.cj 包含 @Derive 和 deriving 导入")

        # --- 7d: 重新运行测试 ---
        agent_plan("重新测试", ["修复枚举注解后重新运行全部测试"])

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.run_test")                                      # 1
        resp = c.execute()

        test2 = resp[1]
        test2_exit = test2.get("data", {}).get("exitCode", -1)
        test2_stdout = test2.get("data", {}).get("stdout", "")
        if test2_exit == 0:
            record(True, "重新测试全部通过 ✅")
            if "Passed" in test2_stdout:
                print(f"    {test2_stdout.strip()}")
            agent_analyse("所有测试通过！迭代修复成功。")
        else:
            test2_stderr = test2.get("data", {}).get("stderr", "")
            record(False, "重新测试",
                   f"exit={test2_exit}\n    stdout: {test2_stdout[:500]}"
                   f"\n    stderr: {test2_stderr[:500]}")

        # ==============================================================
        # 阶段 8 — LSP 工具: 验证语言服务器集成
        # LSP 可能因环境缺少二进制而不可用，测试仅验证调用格式正确
        # ==============================================================
        step("阶段 8: LSP 工具 — 验证语言服务器集成")

        agent_plan("LSP 功能探测", [
            "lsp_status: 检查 LSP 二进制是否可用",
            "lsp_document_symbols: 查询 types.cj 的符号",
            "注意: LSP 可能因环境缺少二进制而返回 ok=false，这是正常的",
        ])

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("cangjie.lsp_status")                                      # 1
        c.call_tool("cangjie.lsp_document_symbols", {                          # 2
            "path": "src/types.cj"
        })
        resp = c.execute()

        # LSP 工具验证: 只检查响应格式是否正确，不要求 ok=true
        # （LSP 需要外部二进制，CI 环境中可能不可用）
        record("ok" in resp[1], "lsp_status: 响应格式正确")
        record("ok" in resp[2], "lsp_document_symbols: 响应格式正确")

        lsp_available = resp[1].get("ok") is True
        agent_analyse(
            f"LSP 状态: {'可用' if lsp_available else '不可用（环境缺少 LSP 二进制）'}。"
            "\n     无论 LSP 是否可用，MCP 工具层都正确处理了请求和响应。"
        )

        # ==============================================================
        # 最终摘要
        # ==============================================================
        step("测试完成 — 最终摘要")
        agent_analyse(
            "TaskManager 项目开发流程完成！"
            "\n     覆盖工具: batch_search, prompt_context, search,"
            "\n               create_file (含 overwrite), list_files, read_file,"
            "\n               search_text, replace_text, rollback,"
            "\n               run_build, run_test,"
            "\n               ast_summary, ast_parse, ast_list_nodes,"
            "\n               ast_query_nodes, ast_query_nodes_with_text,"
            "\n               edit_ast_node,"
            "\n               lsp_status, lsp_document_symbols"
            "\n     迭代过程: 编译失败→修复 import→成功 / 测试失败→修复 @Derive→通过"
            "\n     AST 编辑: edit_ast_node 替换函数 → rollback 恢复"
        )

    except Exception as e:
        print(f"\n  ✗ 致命错误: {e}")
        import traceback
        traceback.print_exc()
        failed += 1
        errors.append(f"fatal: {e}")

    finally:
        if keep_workspace:
            print(f"\n  📁 工作区已保留: {workspace}")
        else:
            shutil.rmtree(workspace, ignore_errors=True)
            print(f"\n  🗑  工作区已清理")

    return passed, failed, errors


# ---------------------------------------------------------------------------
# 入口点
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="端到端测试: AI Agent 通过 MCP 工具开发 TaskManager 项目"
    )
    parser.add_argument(
        "--bin", default=DEFAULT_BIN,
        help="cangjiecoder 可执行文件路径"
    )
    parser.add_argument(
        "--keep", action="store_true",
        help="测试结束后保留生成的工作区"
    )
    args = parser.parse_args()

    print("=" * 64)
    print("  端到端测试: AI Agent 驱动 TaskManager 项目开发")
    print("  (覆盖 AST 编辑、LSP、高级 Skill 查询)")
    print("=" * 64)

    passed, failed, errors = run_e2e(args.bin, args.keep)

    print("\n" + "=" * 64)
    total = passed + failed
    print(f"  结果: {passed} 通过, {failed} 失败, {total} 总计")
    if errors:
        print(f"\n  失败项:")
        for e in errors:
            print(f"    • {e}")
    print("=" * 64)

    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
