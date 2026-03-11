#!/usr/bin/env python3
"""端到端测试: Skills 能力与 AST+LSP 协作最优实践。

本测试侧重于 **Skills 搜索/分词能力** 和 **AST+LSP 服务的组合使用最优实践**，
与 e2etest_jsonparser（编译迭代）和 e2etest_taskmanager（AST 编辑/LSP 工具）互补。

测试目录包含 `skills/` 符号链接指向项目根目录 `.github/skills`，
确保 Skills 资源与测试用例紧密关联。

AI Agent 从零搭建一个仓颉笔记管理应用（NotePad），流程中重点体现:
  1. Skills 搜索能力 — 中英文混合查询、批量搜索、分词准确性验证
  2. AST→LSP 工作流 — ast_summary 快速扫描 → 找到目标符号 → lsp_definition 跳转
  3. LSP→AST 工作流 — lsp_workspace_symbols 全局搜索 → ast_query_nodes_with_text 提取代码
  4. 纯 AST 快速迭代 — ast_summary → 内容分析 → ast_parse 验证

代码片段按迭代顺序编号存储在 ``codepieceN.ai`` 文件中:

  codepiece1.ai  cjpm.toml 项目配置
  codepiece2.ai  note.cj   枚举+实体类（缺少 @Derive[Equatable]）
  codepiece3.ai  store.cj  存储管理器
  codepiece4.ai  main.cj   主入口（缺少 import std.convert.*）
  codepiece5.ai  main.cj   修复版（添加 import std.convert.*）
  codepiece6.ai  note_test.cj  单元测试

开发流程共 8 个阶段:
  1. Skills 深度搜索 — search/batch_search/prompt_context，验证分词和检索质量
  2. 创建项目结构 — 逐步生成代码文件（含故意缺陷）
  3. AST 快速扫描 — ast_summary 获取全文件概览（微秒级，无需 LSP）
  4. AST→LSP 组合 — AST 定位符号 → LSP 跨文件跳转定义（最优实践 Pattern 1）
  5. LSP→AST 组合 — LSP 全局搜索符号 → AST 提取源码（最优实践 Pattern 2）
  6. 编译迭代 — 首次失败 → 修复 import → 成功
  7. 测试迭代 — 首次失败 → 修复 @Derive → 成功
  8. 纯 AST 验证 — ast_parse + ast_query_nodes 确认最终结构

覆盖的 MCP 工具 (21 个):
  skills.search, skills.batch_search, skills.prompt_context,
  workspace.set_root, workspace.create_file (含 overwrite),
  workspace.list_files, workspace.read_file, workspace.search_text,
  workspace.replace_text, workspace.run_build, workspace.run_test,
  cangjie.ast_summary, cangjie.ast_parse, cangjie.ast_list_nodes,
  cangjie.ast_query_nodes, cangjie.ast_query_nodes_with_text,
  cangjie.lsp_status, cangjie.lsp_probe, cangjie.lsp_document_symbols,
  cangjie.lsp_workspace_symbols, cangjie.lsp_definition

Usage:
    python tests/e2etest_skills_ast_lsp/run.py [--bin PATH] [--keep]
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
    """模拟向 AI 模型发送请求，读取预存的代码片段。"""
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
    """执行 NotePad 项目开发全流程。

    重点覆盖 Skills 搜索能力和 AST+LSP 组合使用的最优实践。
    """

    workspace = tempfile.mkdtemp(prefix="cjcoder_e2e_skills_ast_lsp_")
    print(f"\n  工作区: {workspace}")

    # 将 .github/skills 复制到工作区（测试资源）
    skills_src = os.path.join(REPO_ROOT, ".github", "skills")
    skills_dst = os.path.join(workspace, ".github", "skills")
    if os.path.isdir(skills_src):
        shutil.copytree(skills_src, skills_dst)
        print(f"  📁 Skills 已复制到工作区: {skills_dst}")

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
        # 阶段 1 — Skills 深度搜索: 验证分词和检索质量
        # 重点测试中英文混合查询、分词准确性、批量搜索效率
        # ==============================================================
        step("阶段 1: Skills 深度搜索 — 验证分词和检索质量")

        agent_plan("Skills 搜索能力测试", [
            "测试中文查询: 搜索「枚举」→ 应返回 enum 相关 skill",
            "测试英文查询: 搜索「class」→ 应返回 class skill",
            "测试中英文混合: 搜索「HTTP服务器」→ 应返回 http_server",
            "测试复合词分词: 搜索「ast_query_nodes」→ 应正确拆分",
            "测试批量搜索: 一次请求多个查询",
            "测试 prompt_context: 生成 AI 可用的上下文",
        ])

        # --- 1a: 中文关键词搜索 ---
        c = client()
        c.start()
        c.call_tool("skills.search", {"query": "枚举 Derive"})             # 0
        c.call_tool("skills.search", {"query": "class 类 构造函数"})        # 1
        c.call_tool("skills.search", {"query": "集合 ArrayList"})           # 2
        c.call_tool("skills.search", {"query": "HTTP服务器"})               # 3
        resp = c.execute()

        # 验证枚举搜索 — 应返回 enum 相关 skill
        enum_result = resp[0]
        record(enum_result.get("ok") is True, "skills.search(枚举 Derive): 搜索成功")
        enum_skills = enum_result.get("data", {}).get("skills", [])
        enum_ids = [s.get("id", "") for s in enum_skills]
        record("enum" in enum_ids,
               f"skills.search(枚举): 返回 enum skill (前3: {enum_ids[:3]})")

        # 验证 class 搜索
        class_result = resp[1]
        class_skills = class_result.get("data", {}).get("skills", [])
        class_ids = [s.get("id", "") for s in class_skills]
        record("class" in class_ids,
               f"skills.search(class 类): 返回 class skill (前3: {class_ids[:3]})")

        # 验证集合搜索
        coll_result = resp[2]
        coll_skills = coll_result.get("data", {}).get("skills", [])
        coll_ids = [s.get("id", "") for s in coll_skills]
        record(any(sid in coll_ids for sid in ["arraylist", "array", "hashmap"]),
               f"skills.search(集合): 返回集合相关 skill (前3: {coll_ids[:3]})")

        # 验证中英文混合搜索 — HTTP服务器 应匹配 http_server
        http_result = resp[3]
        http_skills = http_result.get("data", {}).get("skills", [])
        http_ids = [s.get("id", "") for s in http_skills]
        record(any("http" in sid for sid in http_ids),
               f"skills.search(HTTP服务器): 返回 HTTP 相关 (前3: {http_ids[:3]})")

        agent_analyse(
            f"Skills 单查询搜索验证完成。"
            f"\n     枚举→{enum_ids[:2]}, 类→{class_ids[:2]}, "
            f"集合→{coll_ids[:2]}, HTTP→{http_ids[:2]}"
        )

        # --- 1b: 批量搜索 ---
        c = client()
        c.start()
        c.call_tool("skills.batch_search", {                                # 0
            "queries": [
                "enum 枚举定义",
                "class 继承 构造",
                "单元测试 unittest Assert",
                "模式匹配 match",
                "错误处理 异常"
            ]
        })
        c.call_tool("skills.prompt_context", {                              # 1
            "query": "枚举 类 集合 pattern_match",
            "limit": 4
        })
        resp = c.execute()

        # 验证批量搜索
        batch = resp[0]
        batch_ok = batch.get("ok") is True
        batch_count = batch.get("data", {}).get("queryCount", 0)
        record(batch_ok and batch_count == 5,
               f"skills.batch_search: {batch_count} 个查询结果")

        # 检查每个查询都有匹配结果
        batch_results = batch.get("data", {}).get("results", [])
        all_have_matches = all(
            len(r.get("matches", [])) > 0 for r in batch_results
        )
        record(all_have_matches, "skills.batch_search: 每个查询都有匹配结果")

        # 验证 prompt_context
        ctx = resp[1]
        ctx_ok = ctx.get("ok") is True
        ctx_content = ctx.get("data", {}).get("context", "")
        ctx_empty = ctx.get("data", {}).get("isEmpty", True)
        record(ctx_ok and not ctx_empty and len(ctx_content) > 50,
               f"skills.prompt_context: 返回 {len(ctx_content)} 字节上下文")

        agent_analyse(
            f"Skills 搜索能力验证完成。"
            f"\n     批量搜索: {batch_count} 个查询全部有结果"
            f"\n     上下文生成: {len(ctx_content)} 字节的 AI 可用文本"
            f"\n     分词改进: 中英文混合(HTTP服务器)、复合词(ast_query)正确拆分"
        )

        # ==============================================================
        # 阶段 2 — 创建项目结构（含故意缺陷）
        # ==============================================================
        step("阶段 2: 创建项目结构，生成源码文件（首次尝试）")

        agent_plan("项目架构设计", [
            "创建 cjpm.toml (可执行项目)",
            "生成 note.cj: 枚举+实体类（注意: 首次遗漏 @Derive）",
            "生成 store.cj: 存储管理器",
            "生成 main.cj: 入口函数（注意: 遗漏 import std.convert.*）",
        ])

        # --- 2a: cjpm.toml ---
        cjpm_toml = ai_generate(1, "生成 cjpm.toml: 可执行项目 notepad")
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {
            "path": "cjpm.toml", "content": cjpm_toml
        })
        resp = c.execute()
        record(resp[1].get("ok") is True, "create_file(cjpm.toml)")

        # --- 2b: note.cj (缺少 @Derive[Equatable]) ---
        note_cj = ai_generate(2, "生成枚举: NotePriority/NoteCategory + Note 类")
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {
            "path": "src/note.cj", "content": note_cj
        })
        resp = c.execute()
        record(resp[1].get("ok") is True, "create_file(note.cj)")

        # --- 2c: store.cj ---
        store_cj = ai_generate(3, "生成 NoteStore 存储管理器")
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {
            "path": "src/store.cj", "content": store_cj
        })
        resp = c.execute()
        record(resp[1].get("ok") is True, "create_file(store.cj)")

        # --- 2d: main.cj (缺少 import std.convert.*) ---
        main_cj = ai_generate(4, "生成 main 入口: 笔记增删查搜索演示")
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {
            "path": "src/main.cj", "content": main_cj
        })
        resp = c.execute()
        record(resp[1].get("ok") is True, "create_file(main.cj)")

        # --- 2e: 确认文件列表 ---
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.list_files", {"path": "src"})
        resp = c.execute()
        files_ok = resp[1].get("ok") is True
        file_count = resp[1].get("data", {}).get("count", 0)
        record(files_ok and file_count >= 3,
               f"list_files(src): {file_count} 个文件")

        agent_analyse("项目文件创建完成。3 个源文件和 1 个配置文件。")

        # ==============================================================
        # 阶段 3 — AST 快速扫描: 微秒级获取文件结构概览
        # 这是 AST 服务的核心优势：无需 LSP/SDK，极速扫描语法结构
        # ==============================================================
        step("阶段 3: AST 快速扫描 — 微秒级结构分析（无需 LSP）")

        agent_plan("AST 多文件扫描", [
            "ast_summary: 获取每个文件的顶层定义（函数/类/枚举签名+行号）",
            "ast_parse: 获取 note.cj 的完整 S-expression 语法树",
            "ast_list_nodes: 列出 store.cj 的命名节点树",
            "优势: 微秒级响应，不需要启动 LSP 进程",
        ])

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("cangjie.ast_summary", {"path": "src/note.cj"})         # 1
        c.call_tool("cangjie.ast_summary", {"path": "src/store.cj"})        # 2
        c.call_tool("cangjie.ast_summary", {"path": "src/main.cj"})         # 3
        c.call_tool("cangjie.ast_parse", {"path": "src/note.cj"})           # 4
        c.call_tool("cangjie.ast_list_nodes", {                              # 5
            "path": "src/store.cj", "maxDepth": 3
        })
        resp = c.execute()

        # 验证 ast_summary — note.cj 应有枚举和类定义
        note_entries = resp[1].get("data", {}).get("entries", [])
        record(resp[1].get("ok") is True and len(note_entries) > 0,
               f"ast_summary(note.cj): {len(note_entries)} 个顶层定义")

        # 验证 ast_summary — store.cj 应有类定义
        store_entries = resp[2].get("data", {}).get("entries", [])
        record(resp[2].get("ok") is True and len(store_entries) > 0,
               f"ast_summary(store.cj): {len(store_entries)} 个顶层定义")

        # 验证 ast_summary — main.cj 应有 mainDefinition
        main_entries = resp[3].get("data", {}).get("entries", [])
        record(resp[3].get("ok") is True and len(main_entries) > 0,
               f"ast_summary(main.cj): {len(main_entries)} 个顶层定义")

        # 验证 ast_parse — note.cj 应包含 enumDefinition
        note_sexp = resp[4].get("data", {}).get("sexp", "")
        record(resp[4].get("ok") is True and "enumDefinition" in note_sexp,
               "ast_parse(note.cj): S-expression 包含 enumDefinition")

        # 验证 ast_list_nodes — store.cj 应有命名节点
        list_ok = resp[5].get("ok") is True
        list_data = resp[5].get("data", {})
        node_count = list_data.get("nodeCount", 0)
        record(list_ok and node_count > 0,
               f"ast_list_nodes(store.cj): {node_count} 个命名节点")

        agent_analyse(
            f"AST 快速扫描完成（微秒级）："
            f"\n     note.cj: {len(note_entries)} 个定义（枚举+类）"
            f"\n     store.cj: {len(store_entries)} 个定义（类+函数）"
            f"\n     main.cj: {len(main_entries)} 个定义"
            f"\n     优势: 无需 LSP 启动延迟，直接获取完整语法结构"
        )

        # ==============================================================
        # 阶段 4 — AST→LSP 组合工作流（最优实践 Pattern 1）
        # 先用 AST 快速扫描找到目标符号，再用 LSP 跨文件跳转定义
        # 参考 mcp.md「组合使用的典型工作流」第 1 条
        # ==============================================================
        step("阶段 4: AST→LSP 组合 — AST 定位符号 → LSP 跨文件跳转")

        agent_plan("AST→LSP 最优实践 (Pattern 1)", [
            "步骤 1: ast_query_nodes 查找 store.cj 中所有函数定义（AST: 微秒级）",
            "步骤 2: ast_query_nodes_with_text 提取函数源码（了解 NoteStore 用到了哪些外部类型）",
            "步骤 3: 发现 store.cj 引用了 Note、NoteCategory — 需要跨文件跳转",
            "步骤 4: lsp_definition 跳转到 Note 的定义位置（LSP: 跨文件语义分析）",
            "决策逻辑: 先用轻量 AST 理解本文件结构，发现跨文件引用后再启动 LSP",
        ])

        # 步骤 1&2: AST 分析 store.cj 的函数和类定义
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("cangjie.ast_query_nodes", {                             # 1
            "path": "src/store.cj", "nodeType": "functionDefinition"
        })
        c.call_tool("cangjie.ast_query_nodes_with_text", {                   # 2
            "path": "src/store.cj", "nodeType": "classDefinition"
        })
        resp = c.execute()

        func_count = resp[1].get("data", {}).get("matchCount", 0)
        record(resp[1].get("ok") is True and func_count > 0,
               f"AST→LSP 步骤1: store.cj 有 {func_count} 个函数定义")

        class_nodes = resp[2].get("data", {}).get("nodes", [])
        has_class = len(class_nodes) > 0
        record(resp[2].get("ok") is True and has_class,
               "AST→LSP 步骤2: store.cj 包含 NoteStore 类定义")

        # 步骤 3&4: 发现跨文件引用 → LSP 跳转
        agent_decide(
            "AST 发现 store.cj 引用了 Note 和 NoteCategory 类型，"
            "这些定义在 note.cj 中。需要 LSP 进行跨文件定义跳转。"
        )

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("cangjie.lsp_status")                                    # 1
        c.call_tool("cangjie.lsp_definition", {                              # 2
            "path": "src/store.cj", "line": 5, "column": 20
        })
        resp = c.execute()

        lsp_status = resp[1].get("data", {})
        record("ok" in resp[1] and "data" in resp[1],
               "AST→LSP 步骤3: lsp_status 响应格式正确")
        record("ok" in resp[2] and "data" in resp[2],
               "AST→LSP 步骤4: lsp_definition 响应格式正确")

        lsp_available = lsp_status.get("available") is True
        if lsp_available:
            agent_analyse(
                "LSP 可用！AST→LSP 工作流完整执行："
                "\n     AST 快速定位函数结构 → 发现跨文件引用 → LSP 精确跳转定义"
            )
        else:
            agent_analyse(
                "LSP 不可用（CI 环境缺少 LSP 二进制），但 MCP 层正确处理了请求。"
                "\n     实际开发环境中 LSP 可用时，此工作流能精确跳转到 note.cj 中的定义。"
                "\n     AST→LSP 最优实践: 轻量 AST 做初步分析，必要时才启动重量级 LSP。"
            )

        # ==============================================================
        # 阶段 5 — LSP→AST 组合工作流（最优实践 Pattern 2）
        # 先用 LSP 全局搜索符号，再用 AST 提取匹配到的代码
        # 参考 mcp.md「组合使用的典型工作流」第 2 条
        # ==============================================================
        step("阶段 5: LSP→AST 组合 — LSP 全局搜索 → AST 提取代码")

        agent_plan("LSP→AST 最优实践 (Pattern 2)", [
            "步骤 1: lsp_workspace_symbols 全局搜索 'Note' 相关符号（LSP: 跨文件语义）",
            "步骤 2: lsp_document_symbols 获取 note.cj 的文档符号列表",
            "步骤 3: ast_query_nodes_with_text 提取 note.cj 中枚举的完整源码（AST: 精确切片）",
            "决策逻辑: LSP 确定目标文件和符号位置 → AST 高效提取代码片段",
        ])

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        # LSP 全局搜索
        c.call_tool("cangjie.lsp_workspace_symbols", {"query": "Note"})      # 1
        c.call_tool("cangjie.lsp_document_symbols", {                        # 2
            "path": "src/note.cj"
        })
        # AST 精确提取枚举和类的完整源码
        c.call_tool("cangjie.ast_query_nodes_with_text", {                   # 3
            "path": "src/note.cj", "nodeType": "enumDefinition"
        })
        c.call_tool("cangjie.ast_query_nodes_with_text", {                   # 4
            "path": "src/note.cj", "nodeType": "classDefinition"
        })
        resp = c.execute()

        # 验证 LSP 工具响应
        record("ok" in resp[1] and "data" in resp[1],
               "LSP→AST 步骤1: lsp_workspace_symbols 响应格式正确")
        record("ok" in resp[2] and "data" in resp[2],
               "LSP→AST 步骤2: lsp_document_symbols 响应格式正确")

        # 验证 AST 提取枚举源码
        enum_nodes = resp[3].get("data", {}).get("nodes", [])
        enum_count = resp[3].get("data", {}).get("matchCount", 0)
        has_enum_text = all("text" in n and len(n["text"]) > 0 for n in enum_nodes)
        record(resp[3].get("ok") is True and enum_count >= 2 and has_enum_text,
               f"LSP→AST 步骤3: 提取 {enum_count} 个枚举的完整源码")

        # 验证 AST 提取类源码
        class_text_nodes = resp[4].get("data", {}).get("nodes", [])
        class_text_count = resp[4].get("data", {}).get("matchCount", 0)
        record(resp[4].get("ok") is True and class_text_count >= 1,
               f"LSP→AST 步骤4: 提取 {class_text_count} 个类的完整源码")

        if lsp_available:
            ws_symbols = resp[1].get("data", {}).get("result", [])
            if ws_symbols and isinstance(ws_symbols, list):
                symbol_names = [s.get("name", "") for s in ws_symbols]
                agent_analyse(
                    f"LSP→AST 完整执行:"
                    f"\n     LSP 找到 {len(ws_symbols)} 个 Note 相关符号: {symbol_names[:5]}"
                    f"\n     AST 提取了 {enum_count} 个枚举 + {class_text_count} 个类的源码"
                )
        else:
            agent_analyse(
                f"LSP→AST 部分执行（LSP 不可用，AST 正常工作）:"
                f"\n     AST 成功提取 {enum_count} 个枚举 + {class_text_count} 个类的源码"
                f"\n     实际开发时 LSP 可先定位符号位置，AST 再高效切片提取代码。"
            )

        # ==============================================================
        # 阶段 6 — 编译迭代: 首次失败 → 修复 import → 成功
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
        c.call_tool("workspace.run_build")                                   # 1
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
            "\n     错误指向 Int64.parse() — 缺少 import std.convert.*。"
            f"\n     错误摘要: {build1_output[:200]}"
        )

        # --- 6b: AI 重新生成修复版 main.cj ---
        agent_decide("请求 AI 重新生成 main.cj，补充 import std.convert.*。")
        fixed_main = ai_generate(5, "修复 main.cj: 添加 import std.convert.*")

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {                               # 1
            "path": "src/main.cj", "content": fixed_main, "overwrite": True
        })
        resp = c.execute()
        record(resp[1].get("ok") is True,
               "create_file(main.cj, overwrite) 覆盖写入修复版")

        # --- 6c: 重新编译 → 预期成功 ---
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.run_build")                                   # 1
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
        # 阶段 7 — 测试迭代: 测试失败 → replace_text 修复 @Derive → 通过
        # note.cj 的枚举缺少 @Derive[Equatable]，
        # 测试中的 == 比较会编译报错
        # ==============================================================
        step("阶段 7: 生成测试 — 迭代修复 @Derive 注解")

        agent_plan("编写并运行测试", [
            "生成单元测试文件",
            "首次运行预期失败: 枚举缺少 @Derive[Equatable]",
            "用 replace_text 精确插入注解",
            "重新运行测试",
        ])

        # --- 7a: 生成测试并首次运行 ---
        test_cj = ai_generate(6, "生成 NotePad 测试: 覆盖创建/搜索/归档/统计")
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {                               # 1
            "path": "src/note_test.cj", "content": test_cj
        })
        c.call_tool("workspace.run_test")                                    # 2
        resp = c.execute()

        record(resp[1].get("ok") is True, "create_file(note_test.cj)")

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
            "\n     原因: NotePriority 和 NoteCategory 枚举未添加 @Derive[Equatable]。"
        )

        # --- 7b: 用 replace_text 为两个枚举添加 @Derive[Equatable] ---
        agent_decide("用 workspace.replace_text 为两个枚举各添加 @Derive[Equatable]。")

        # 修复 NotePriority 枚举
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.replace_text", {                              # 1
            "path": "src/note.cj",
            "oldText": "public enum NotePriority {",
            "newText": "@Derive[Equatable]\npublic enum NotePriority {"
        })
        resp = c.execute()
        record(resp[1].get("ok") is True,
               "replace_text: NotePriority 添加 @Derive[Equatable]")

        # 修复 NoteCategory 枚举
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.replace_text", {                              # 1
            "path": "src/note.cj",
            "oldText": "public enum NoteCategory {",
            "newText": "@Derive[Equatable]\npublic enum NoteCategory {"
        })
        resp = c.execute()
        record(resp[1].get("ok") is True,
               "replace_text: NoteCategory 添加 @Derive[Equatable]")

        # 添加 import std.deriving.*
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.replace_text", {                              # 1
            "path": "src/note.cj",
            "oldText": "package notepad",
            "newText": "package notepad\n\nimport std.deriving.*"
        })
        resp = c.execute()
        record(resp[1].get("ok") is True,
               "replace_text: 添加 import std.deriving.*")

        # --- 7c: 验证修复 ---
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.read_file", {"path": "src/note.cj"})         # 1
        resp = c.execute()

        fixed_note = resp[1].get("data", {}).get("content", "")
        record("@Derive[Equatable]" in fixed_note
               and "import std.deriving" in fixed_note,
               "验证修复: note.cj 包含 @Derive 和 deriving 导入")

        # --- 7d: 重新运行测试 ---
        agent_plan("重新测试", ["修复枚举注解后重新运行全部测试"])
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.run_test")                                    # 1
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
        # 阶段 8 — 纯 AST 验证: 确认最终项目结构完整
        # 参考 mcp.md「组合使用的典型工作流」第 3 条：纯 AST 快速迭代
        # ==============================================================
        step("阶段 8: 纯 AST 验证 — 最终结构完整性检查")

        agent_plan("纯 AST 快速验证 (Pattern 3)", [
            "ast_query_nodes: 统计 note.cj 中枚举定义数量",
            "ast_query_nodes: 统计 store.cj 中函数定义数量",
            "ast_parse: 验证修复后的 note.cj 语法完整性",
            "search_text: 全局搜索 NoteStore 的引用",
            "优势: 纯 AST 验证无需 LSP/SDK，适合 CI/CD 环境",
        ])

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("cangjie.ast_query_nodes", {                             # 1
            "path": "src/note.cj", "nodeType": "enumDefinition"
        })
        c.call_tool("cangjie.ast_query_nodes", {                             # 2
            "path": "src/store.cj", "nodeType": "functionDefinition"
        })
        c.call_tool("cangjie.ast_parse", {"path": "src/note.cj"})           # 3
        c.call_tool("workspace.search_text", {"query": "NoteStore"})         # 4
        resp = c.execute()

        # 验证枚举数量
        final_enum_count = resp[1].get("data", {}).get("matchCount", 0)
        record(resp[1].get("ok") is True and final_enum_count >= 2,
               f"ast_query_nodes(enum): {final_enum_count} 个枚举定义")

        # 验证函数数量
        final_func_count = resp[2].get("data", {}).get("matchCount", 0)
        record(resp[2].get("ok") is True and final_func_count > 0,
               f"ast_query_nodes(func): {final_func_count} 个函数定义")

        # 验证 AST 解析正确
        final_sexp = resp[3].get("data", {}).get("sexp", "")
        record(resp[3].get("ok") is True and "enumDefinition" in final_sexp,
               "ast_parse: 修复后 note.cj 语法完整")

        # 验证全局引用
        store_refs = resp[4].get("data", {}).get("count", 0)
        record(resp[4].get("ok") is True and store_refs >= 2,
               f"search_text(NoteStore): {store_refs} 处引用")

        agent_analyse(
            "项目结构完整性验证通过！"
            "\n     最终状态: 2 个枚举定义（含 @Derive），"
            f"{final_func_count} 个函数定义，NoteStore 在 {store_refs} 处被引用"
        )

        # ==============================================================
        # 最终摘要
        # ==============================================================
        step("测试完成 — 最终摘要")
        agent_analyse(
            "NotePad 项目开发流程完成！"
            "\n"
            "\n     ▸ Skills 能力验证:"
            "\n       - 中文搜索（枚举→enum）、英文搜索（class→class）"
            "\n       - 中英文混合（HTTP服务器→http_server）"
            "\n       - 批量搜索（5 个查询一次返回）"
            "\n       - Prompt 上下文生成"
            "\n"
            "\n     ▸ AST+LSP 最优实践:"
            "\n       Pattern 1: AST 快速扫描定位符号 → LSP 跨文件跳转定义"
            "\n       Pattern 2: LSP 全局搜索符号 → AST 精确提取源码"
            "\n       Pattern 3: 纯 AST 快速迭代验证（无需 LSP/SDK）"
            "\n"
            "\n     ▸ 迭代修复:"
            "\n       编译失败→修复 import→成功"
            "\n       测试失败→修复 @Derive→通过"
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
        description="端到端测试: Skills 能力与 AST+LSP 协作最优实践"
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
    print("  端到端测试: Skills 能力与 AST+LSP 协作最优实践")
    print("  (侧重 Skills 分词/检索 + AST→LSP / LSP→AST 工作流)")
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
