#!/usr/bin/env python3
"""端到端测试: 模拟 AI Agent 通过 MCP 工具驱动 JsonParser 项目开发。

本脚本模拟一个完整的 AI 编程会话，使用 MCP 工具接口从零开始开发一个
仓颉语言 JSON 解析器项目。整个流程包含 **故意的编译错误和迭代修复**，
真实还原 AI 编码 → 编译 → 分析 → 修复 的循环过程。

AI 生成的代码片段存储在 ``codepieceN.ai`` 文件中，按迭代出现顺序编号:

  codepiece1.ai  cjpm.toml 项目配置
  codepiece2.ai  json_value.cj  (首次生成, 缺少 @Derive[Equatable])
  codepiece3.ai  json_lexer.cj  (正确)
  codepiece4.ai  json_parser.cj (首次生成, 缺少 import std.convert.*)
  codepiece5.ai  main.cj        (正确)
  codepiece6.ai  json_parser.cj (AI 修复版, 补充了 import std.convert.*)
  codepiece7.ai  json_parser_test.cj (单元测试)

``ai_generate()`` 模拟向 AI 模型发送请求并获取代码,
``agent_plan()``  模拟 Agent 的规划推理,
``agent_analyse()`` 模拟 Agent 对工具输出的分析,
``agent_decide()``  模拟 Agent 做出行动决策。

开发流程共 7 个阶段:
  1. 搜索仓颉 Skill 知识，了解 JSON 处理和语法要点
  2. 创建项目结构，逐步生成源码文件 (初始代码含缺陷)
  3. AST 分析验证代码结构
  4. 读取文件验证内容正确性
  5. 首次编译 → 失败 → Agent 分析错误 → AI 重新生成 → 再次编译 → 成功
  6. 生成测试 → 测试编译失败 → Agent 定位问题 → 修复 → 测试通过
  7. 最终 AST 验证确认项目完整性

Usage:
    python tests/e2etest_jsonparser/run.py [--bin PATH] [--keep]
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
    """模拟向 AI 模型发送请求，获取代码生成结果。

    在真实 Agent 中，这里会调用 LLM API (如 OpenAI/Claude 等)。
    为了让测试确定性可复现，我们从预先编写的 ``codepieceN.ai`` 文件
    中读取内容，模拟 AI 的输出。

    Args:
        piece_id: 代码片段编号，映射到 ``codepiece<id>.ai`` 文件。
        prompt:   模拟发送给 AI 模型的提示词（仅用于日志记录，不实际使用）。

    Returns:
        AI "生成"的代码内容字符串。
    """
    path = os.path.join(SCRIPT_DIR, f"codepiece{piece_id}.ai")
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    label = os.path.basename(path)
    print(f"  🤖 AI 模型响应 ← {label}  ({len(content)} 字节)")
    if prompt:
        # 截断过长的 prompt，只显示前 80 个字符
        display = prompt[:80] + ('…' if len(prompt) > 80 else '')
        print(f"     提示词: {display}")
    return content


def agent_plan(title, details):
    """模拟 Agent 的规划推理过程 — 类似思维链 (Chain-of-Thought)。

    Agent 在执行每个阶段前会先制定计划，列出要完成的步骤。
    """
    print(f"\n  📋 Agent 规划: {title}")
    for line in details:
        print(f"     • {line}")


def agent_analyse(summary):
    """模拟 Agent 对工具返回结果的分析。

    Agent 每次调用 MCP 工具后，会分析返回的数据，
    判断是否符合预期，以决定下一步行动。
    """
    print(f"  🔍 Agent 分析: {summary}")


def agent_decide(decision):
    """模拟 Agent 做出行动决策。

    当 Agent 发现问题（如编译错误）时，会决定采取修复措施。
    """
    print(f"  💡 Agent 决策: {decision}")


# ---------------------------------------------------------------------------
# 测试编排辅助函数
# ---------------------------------------------------------------------------

def step(msg):
    """打印阶段横幅，标识测试流程的主要阶段。"""
    print(f"\n{'─' * 64}")
    print(f"  🔧  {msg}")
    print(f"{'─' * 64}")


# ---------------------------------------------------------------------------
# 主 e2e 测试场景
# ---------------------------------------------------------------------------

def run_e2e(service_bin, keep_workspace):
    """执行完整的 JsonParser 项目开发场景。

    模拟一个 AI Agent 从零开始开发 JSON 解析器的全过程:
    - 搜索 Skill 获取领域知识
    - 逐步生成代码 (初始版本含 bug)
    - 编译 → 失败 → 分析错误 → 修复 → 重新编译 (迭代)
    - 生成测试 → 运行 → 失败 → 修复 → 重新测试 (迭代)
    - 最终验证项目完整性
    """

    # 创建临时工作区，模拟 Agent 的项目目录
    workspace = tempfile.mkdtemp(prefix="cjcoder_e2e_jsonparser_")
    print(f"\n  工作区: {workspace}")

    passed = 0
    failed = 0
    errors = []

    def record(ok, name, detail=""):
        """记录单个检查点的通过/失败状态。"""
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
        """创建一个新的 MCP 客户端会话。"""
        return McpClient(workspace=workspace, service_bin=service_bin)

    try:
        # ==============================================================
        # 阶段 1 — 知识收集: 搜索仓颉语言相关 Skill
        # ==============================================================
        step("阶段 1: 搜索仓颉 Skill，收集 JSON 解析领域知识")

        agent_plan("收集领域知识", [
            "搜索 JSON 解析相关 Skill，了解仓颉语言的 JSON 处理方式",
            "搜索 enum / class / 单元测试 Skill，确认语法要点和最佳实践",
            "根据 Skill 搜索结果制定技术方案",
        ])

        # 批量发送 4 个 Skill 搜索请求
        c = client()
        c.start()
        c.call_tool("skills.search", {"query": "JSON 解析"})
        c.call_tool("skills.search", {"query": "enum 枚举"})
        c.call_tool("skills.search", {"query": "单元测试 unittest"})
        c.call_tool("skills.search", {"query": "class 类定义"})
        resp = c.execute()

        # 验证每个搜索都返回了结果
        for i, topic in enumerate(["JSON", "enum", "unittest", "class"]):
            record(resp[i].get("ok") is True, f"skills.search({topic})")

        agent_analyse(
            "Skill 搜索全部成功。获取到 JSON 处理、枚举定义、单元测试和类定义的参考资料。"
            "\n     关键发现: ① 枚举需要 @Derive[Equatable] 才能用 =="
            "\n              ② Float64.parse 需要 import std.convert.*"
            "\n              ③ String 的 s[i] 返回 Byte 而非 Rune，需用 toRuneArray()"
        )

        # ==============================================================
        # 阶段 2 — 项目搭建: 创建工作区和源码文件
        # AI 首次生成的代码可能包含错误（这是正常的）
        # ==============================================================
        step("阶段 2: 初始化项目，逐步生成源码文件（首次尝试）")

        agent_plan("项目架构设计", [
            "创建 cjpm.toml 配置文件 (可执行项目, SDK 1.0.5)",
            "按依赖顺序生成源码: 数据模型 → 词法分析 → 解析器 → 入口",
            "每个文件生成后立即写入工作区",
            "注意: AI 首次生成的代码可能有遗漏，后续通过编译反馈来修正",
        ])

        # --- 2a: 生成项目配置文件 ---
        cjpm_toml = ai_generate(1, "生成 cjpm.toml: 项目名 jsonparser, 可执行类型, SDK 1.0.5")

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {
            "path": "cjpm.toml", "content": cjpm_toml
        })
        resp = c.execute()
        record(resp[1].get("ok") is True, "create_file(cjpm.toml)")

        agent_analyse("项目配置文件创建成功，开始逐步生成源码。")

        # --- 2b: 生成数据模型 (json_value.cj) ---
        # 注意: 这个版本 AI 忘记给枚举加 @Derive[Equatable]，后续测试阶段会暴露
        json_value_cj = ai_generate(
            2, "生成 JSON 值类型定义: enum JsonValueKind (Null/Bool/Number/String/"
               "Array/Object) + class JsonValue 数据模型，包含工厂方法和 display()"
        )

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {
            "path": "src/json_value.cj", "content": json_value_cj
        })
        resp = c.execute()
        record(resp[1].get("ok") is True, "create_file(json_value.cj)")

        # --- 2c: 生成词法分析器 (json_lexer.cj) ---
        json_lexer_cj = ai_generate(
            3, "生成 JSON 词法分析器: enum TokenKind + class JsonLexer, "
               "基于 Rune 数组逐字符扫描，支持字符串转义和数字(含科学计数法)"
        )

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {
            "path": "src/json_lexer.cj", "content": json_lexer_cj
        })
        resp = c.execute()
        record(resp[1].get("ok") is True, "create_file(json_lexer.cj)")

        # --- 2d: 生成解析器 (json_parser.cj) ---
        # 注意: 这个版本 AI 忘记了 import std.convert.*，编译阶段会暴露
        json_parser_cj = ai_generate(
            4, "生成递归下降 JSON 解析器: class JsonParser + ParseResult, "
               "支持 null/bool/number/string/array/object, 入口函数 parseJson()"
        )

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {
            "path": "src/json_parser.cj", "content": json_parser_cj
        })
        resp = c.execute()
        record(resp[1].get("ok") is True, "create_file(json_parser.cj)")

        # --- 2e: 生成主入口 (main.cj) ---
        main_cj = ai_generate(
            5, "生成演示入口 main.cj: 解析完整 JSON 对象、嵌套结构、各种基本类型"
        )

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {
            "path": "src/main.cj", "content": main_cj
        })
        resp = c.execute()
        record(resp[1].get("ok") is True, "create_file(main.cj)")

        agent_analyse("所有源码文件已创建。AI 首次生成的代码可能有遗漏，"
                      "先进行 AST 结构分析，再通过编译来验证。")

        # --- 2f: 确认文件列表 ---
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.list_files", {"path": "src"})
        resp = c.execute()

        files_ok = resp[1].get("ok") is True
        file_count = resp[1].get("data", {}).get("count", 0) if files_ok else 0
        record(files_ok and file_count >= 4,
               f"list_files(src): 发现 {file_count} 个文件")

        # ==============================================================
        # 阶段 3 — 代码审查: 用 AST 工具分析代码结构
        # (AST 分析是语法级别的，即使有语义错误也能工作)
        # ==============================================================
        step("阶段 3: 使用 AST 工具分析代码结构")

        agent_plan("代码结构审查", [
            "用 ast_summary 获取每个源文件的顶层定义摘要",
            "用 ast_parse 验证 main.cj 的 AST 结构是否正确",
            "用 ast_query_nodes_with_text 列出解析器中所有函数定义",
            "注意: AST 分析只检查语法结构，不检查语义正确性（如缺少 import）",
        ])

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        # ast_summary 检查各文件的顶层定义
        c.call_tool("cangjie.ast_summary", {"path": "src/json_value.cj"})     # 1
        c.call_tool("cangjie.ast_summary", {"path": "src/json_lexer.cj"})     # 2
        c.call_tool("cangjie.ast_summary", {"path": "src/json_parser.cj"})    # 3
        # ast_parse 获取完整 AST
        c.call_tool("cangjie.ast_parse", {"path": "src/main.cj"})             # 4
        # ast_query_nodes_with_text 查询函数定义
        c.call_tool("cangjie.ast_query_nodes_with_text", {                     # 5
            "path": "src/json_parser.cj",
            "nodeType": "functionDefinition"
        })
        resp = c.execute()

        # 检查 json_value.cj 的摘要 — 应包含 enum 和 class 定义
        sv_ok = resp[1].get("ok") is True
        sv_entries = resp[1].get("data", {}).get("entries", [])
        record(sv_ok and len(sv_entries) > 0,
               f"ast_summary(json_value.cj): {len(sv_entries)} 个顶层定义")

        # 检查 json_lexer.cj 的摘要
        record(resp[2].get("ok") is True, "ast_summary(json_lexer.cj)")

        # 检查 json_parser.cj 的摘要
        record(resp[3].get("ok") is True, "ast_summary(json_parser.cj)")

        # 检查 main.cj 的 AST 中包含 mainDefinition 节点
        pm_sexp = resp[4].get("data", {}).get("sexp", "")
        record(resp[4].get("ok") is True and "mainDefinition" in pm_sexp,
               "ast_parse(main.cj): 包含 mainDefinition 节点")

        # 检查解析器中的函数数量
        qf_count = resp[5].get("data", {}).get("matchCount", 0) \
            if resp[5].get("ok") else 0
        record(qf_count > 0,
               f"ast_query_nodes_with_text(functionDefinition): {qf_count} 个函数")

        agent_analyse(
            f"AST 分析完成: json_value.cj 有 {len(sv_entries)} 个顶层定义, "
            f"json_parser.cj 有 {qf_count} 个函数。"
            "\n     语法结构正确，但语义错误需要编译器才能发现。"
        )

        # ==============================================================
        # 阶段 4 — 内容验证: 读取文件并搜索关键内容
        # ==============================================================
        step("阶段 4: 读取文件并交叉验证内容")

        agent_plan("内容交叉验证", [
            "读取 cjpm.toml 确认项目名和配置",
            "读取 json_value.cj 确认核心类型定义",
            "读取 json_parser.cj 确认解析器实现",
            "全局搜索 parseJson 确认函数引用关系",
        ])

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.read_file", {"path": "cjpm.toml"})             # 1
        c.call_tool("workspace.read_file", {"path": "src/json_value.cj"})     # 2
        c.call_tool("workspace.read_file", {"path": "src/json_parser.cj"})    # 3
        c.call_tool("workspace.search_text", {"query": "parseJson"})           # 4
        resp = c.execute()

        # 验证 cjpm.toml 包含正确的项目名
        toml_content = resp[1].get("data", {}).get("content", "")
        record('name = "jsonparser"' in toml_content,
               "cjpm.toml 包含正确的包名")

        # 验证 json_value.cj 包含核心类型
        jv_content = resp[2].get("data", {}).get("content", "")
        record("class JsonValue" in jv_content
               and "enum JsonValueKind" in jv_content,
               "json_value.cj 包含 JsonValue 类和 JsonValueKind 枚举")

        # 验证 json_parser.cj 包含解析器
        jp_content = resp[3].get("data", {}).get("content", "")
        record("func parseJson" in jp_content
               and "class JsonParser" in jp_content,
               "json_parser.cj 包含 JsonParser 类和 parseJson 函数")

        # 验证 parseJson 在多处被引用
        sr_count = resp[4].get("data", {}).get("count", 0)
        record(resp[4].get("ok") is True and sr_count >= 2,
               f"search_text(parseJson): 在 {sr_count} 处找到引用")

        agent_analyse("文件内容验证通过，代码结构完整。准备首次编译。")

        # ==============================================================
        # 阶段 5 — 编译迭代: 首次编译 → 失败 → 分析修复 → 重新编译
        # 这是真实 AI 开发中最常见的场景：AI 生成的代码通常无法
        # 一次编译通过，需要根据错误信息迭代修复
        # ==============================================================
        step("阶段 5: 编译项目 — 迭代修复编译错误")

        # --- 5a: 首次编译 → 预期失败 ---
        agent_plan("首次编译尝试", [
            "执行 workspace.run_build 编译项目",
            "预期结果: 编译可能因 AI 代码遗漏而失败",
            "如果失败，分析错误信息并请求 AI 修复",
        ])

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.run_build")                                     # 1
        resp = c.execute()

        build1 = resp[1]
        build1_exit = build1.get("data", {}).get("exitCode", -1)
        build1_stderr = build1.get("data", {}).get("stderr", "")
        build1_stdout = build1.get("data", {}).get("stdout", "")

        # 首次编译应该失败（因为 json_parser.cj 缺少 import std.convert.*）
        record(build1_exit != 0,
               "首次编译失败（预期行为，AI 代码有遗漏）")

        agent_analyse(
            f"编译失败 (exit={build1_exit})。"
            "\n     分析编译器错误输出，定位问题根源..."
            f"\n     错误摘要: {build1_stderr[:200] if build1_stderr else build1_stdout[:200]}"
        )

        # --- 5b: 分析错误，读取问题文件 ---
        agent_decide(
            "错误指向 json_parser.cj 中的 Float64.parse() 调用。"
            "\n     原因: 缺少 import std.convert.* — 仓颉语言的类型转换方法"
            "定义在 std.convert 包中。"
            "\n     行动: 读取当前文件确认问题，然后请求 AI 重新生成修复版本。"
        )

        # 读取问题文件，确认缺少 import
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.read_file", {"path": "src/json_parser.cj"})    # 1
        resp = c.execute()

        parser_content = resp[1].get("data", {}).get("content", "")
        # 验证确实缺少 import std.convert.*
        record("import std.convert" not in parser_content,
               "确认 json_parser.cj 缺少 import std.convert.*")

        agent_analyse(
            "已确认: json_parser.cj 的 import 部分只有 std.collection.*，"
            "缺少 std.convert.* (提供 Float64.parse() 等类型转换方法)。"
        )

        # --- 5c: 请求 AI 修复并重写文件 ---
        agent_decide(
            "请求 AI 重新生成 json_parser.cj，在 import 部分补充 std.convert.*。"
            "\n     使用 workspace.create_file 的 overwrite 模式覆盖旧文件。"
        )

        # AI 重新生成修复版本的 json_parser.cj（codepiece6.ai）
        fixed_parser = ai_generate(
            6, "修复 json_parser.cj: 在 import std.collection.* 后添加 "
               "import std.convert.* 以支持 Float64.parse() 调用"
        )

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        # 使用 overwrite: True 覆盖已有文件
        c.call_tool("workspace.create_file", {                                 # 1
            "path": "src/json_parser.cj",
            "content": fixed_parser,
            "overwrite": True
        })
        resp = c.execute()
        record(resp[1].get("ok") is True,
               "create_file(json_parser.cj, overwrite=True) 覆盖写入成功")

        agent_analyse("修复版 json_parser.cj 已写入，准备第二次编译。")

        # --- 5d: 第二次编译 → 预期成功 ---
        agent_plan("重新编译", [
            "修复了 import 遗漏后再次编译",
            "预期结果: 编译通过",
        ])

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.run_build")                                     # 1
        resp = c.execute()

        build2 = resp[1]
        build2_exit = build2.get("data", {}).get("exitCode", -1)
        if build2_exit == 0:
            record(True, "第二次编译成功 ✅")
            agent_analyse("编译通过！import 修复有效。准备添加单元测试。")
        else:
            build2_stderr = build2.get("data", {}).get("stderr", "")
            record(False, "第二次编译",
                   f"exit={build2_exit}, stderr={build2_stderr[:300]}")

        # ==============================================================
        # 阶段 6 — 测试迭代: 生成测试 → 测试编译失败 → 修复 → 通过
        # 这一阶段模拟另一种常见的 AI 开发问题:
        # 测试代码编译时才暴露的类型系统错误
        # ==============================================================
        step("阶段 6: 生成单元测试 — 迭代修复类型错误")

        # --- 6a: 生成测试代码并首次运行 ---
        agent_plan("编写并运行单元测试", [
            "请求 AI 生成覆盖全部 JSON 类型的测试文件",
            "写入 src/json_parser_test.cj",
            "执行 workspace.run_test 运行测试",
            "注意: 测试可能因为数据模型的类型定义问题而编译失败",
        ])

        test_cj = ai_generate(
            7, "生成 JsonParser 完整单元测试: 覆盖 null/bool/integer/float/"
               "scientific/string/escape/empty-array/array/mixed-array/"
               "empty-object/object/nested/whitespace/error-cases/display"
        )

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {                                 # 1
            "path": "src/json_parser_test.cj", "content": test_cj
        })
        c.call_tool("workspace.run_test")                                      # 2
        resp = c.execute()

        record(resp[1].get("ok") is True, "create_file(json_parser_test.cj)")

        test1 = resp[2]
        test1_exit = test1.get("data", {}).get("exitCode", -1)
        test1_stderr = test1.get("data", {}).get("stderr", "")
        test1_stdout = test1.get("data", {}).get("stdout", "")

        # 首次测试运行应该失败（因为 json_value.cj 的枚举缺少 @Derive[Equatable]，
        # 测试代码中使用 == 比较枚举值时会编译报错）
        record(test1_exit != 0,
               "首次测试编译失败（预期行为，枚举缺少 @Derive 注解）")

        agent_analyse(
            f"测试编译失败 (exit={test1_exit})。"
            "\n     分析错误: 测试代码使用 kind == JsonValueKind.JNull 比较枚举值，"
            "\n     但 JsonValueKind 枚举未添加 @Derive[Equatable] 注解。"
            "\n     仓颉语言要求枚举类型显式添加 @Derive[Equatable] 才能使用 == 运算符。"
            f"\n     错误摘要: {test1_stderr[:200] if test1_stderr else test1_stdout[:200]}"
        )

        # --- 6b: 分析错误，读取问题文件，用 replace_text 修复 ---
        agent_decide(
            "问题在 src/json_value.cj: enum JsonValueKind 缺少 @Derive[Equatable]。"
            "\n     使用 workspace.replace_text 精确插入注解，无需重写整个文件。"
            "\n     这比整文件覆盖更高效，也更符合真实 Agent 的修复策略。"
        )

        # 先读取文件确认问题
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.read_file", {"path": "src/json_value.cj"})     # 1
        resp = c.execute()

        value_content = resp[1].get("data", {}).get("content", "")
        record("@Derive[Equatable]" not in value_content,
               "确认 json_value.cj 枚举缺少 @Derive[Equatable]")

        # 使用 replace_text 精确插入 @Derive[Equatable] 注解
        # 这是 Agent 常用的修复策略: 用最小改动修复问题
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.replace_text", {                                # 1
            "path": "src/json_value.cj",
            "oldText": "// JSON 值类型枚举\npublic enum JsonValueKind {",
            "newText": "// JSON 值类型枚举\n@Derive[Equatable]\npublic enum JsonValueKind {"
        })
        resp = c.execute()
        record(resp[1].get("ok") is True,
               "replace_text: 为枚举插入 @Derive[Equatable]")

        agent_analyse("已通过 replace_text 为 JsonValueKind 添加 @Derive[Equatable] 注解。"
                      "\n     准备重新运行测试。")

        # --- 6c: 重新运行测试 → 预期全部通过 ---
        agent_plan("重新测试", [
            "修复了枚举注解后重新运行全部单元测试",
            "预期结果: 所有测试通过",
        ])

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
            agent_analyse("所有单元测试通过！两轮迭代修复了所有问题。")
        else:
            test2_stderr = test2.get("data", {}).get("stderr", "")
            record(False, "重新测试",
                   f"exit={test2_exit}\n    stdout: {test2_stdout[:500]}"
                   f"\n    stderr: {test2_stderr[:500]}")

        # ==============================================================
        # 阶段 7 — 最终验证: AST 分析确认项目完整性
        # ==============================================================
        step("阶段 7: 最终验证 — AST 分析确认项目完整性")

        agent_plan("最终完整性检查", [
            "AST 分析测试文件，确认测试类正确识别",
            "查询 json_value.cj 的枚举定义数量",
            "列出全部文件确认项目结构完整",
        ])

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("cangjie.ast_summary", {                                   # 1
            "path": "src/json_parser_test.cj"
        })
        c.call_tool("cangjie.ast_query_nodes", {                               # 2
            "path": "src/json_value.cj",
            "nodeType": "enumDefinition"
        })
        c.call_tool("workspace.list_files")                                    # 3
        resp = c.execute()

        # 验证测试文件的 AST 摘要包含测试类
        ts_text = resp[1].get("data", {}).get("summary", "")
        record(resp[1].get("ok") is True and "class" in ts_text.lower(),
               "ast_summary(测试文件) 检测到测试类定义")

        # 验证 json_value.cj 的枚举定义
        eq_count = resp[2].get("data", {}).get("matchCount", 0)
        record(resp[2].get("ok") is True and eq_count >= 1,
               f"ast_query_nodes(enumDefinition): 找到 {eq_count} 个枚举")

        # 验证最终文件数量
        fl_count = resp[3].get("data", {}).get("count", 0)
        record(resp[3].get("ok") is True and fl_count >= 6,
               f"list_files: 共 {fl_count} 个文件")

        agent_analyse(
            f"项目完整性验证通过: "
            f"测试类已识别, {eq_count} 个枚举定义, 共 {fl_count} 个文件。"
            "\n     🎉 JsonParser 项目开发流程全部完成！"
            "\n     迭代过程: 首次编译失败 → 修复 import → 编译通过 → "
            "测试编译失败 → 修复 @Derive → 测试通过"
        )

    except Exception as e:
        print(f"\n  ✗ 致命错误: {e}")
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
        description="端到端测试: 模拟 AI Agent 通过 MCP 工具开发 JsonParser 项目"
    )
    parser.add_argument(
        "--bin", default=DEFAULT_BIN,
        help="cangjiecoder 可执行文件路径"
    )
    parser.add_argument(
        "--keep", action="store_true",
        help="测试结束后保留生成的工作区，不自动清理"
    )
    args = parser.parse_args()

    print("=" * 64)
    print("  端到端测试: AI Agent 驱动 JsonParser 项目开发 (MCP 工具)")
    print("=" * 64)

    passed, failed, errors = run_e2e(args.bin, args.keep)

    # 打印测试摘要
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
