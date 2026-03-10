# CangjieCoder Service MCP 工具参考

本文档详细介绍 `service` 提供的每一个 MCP 工具的功能、参数、实现原理和使用示例，并给出 stdio MCP Server 接入主流 AI 开发工具的配置方法。

---

## 目录

- [概述](#概述)
- [工具总览](#工具总览)
- [技能搜索](#1-skillssearch)
- [工作区文件操作](#工作区文件操作)
  - [workspace.read_file](#2-workspaceread_file)
  - [workspace.list_files](#3-workspacelist_files)
  - [workspace.search_text](#4-workspacesearch_text)
  - [workspace.replace_text](#5-workspacereplace_text)
  - [workspace.create_file](#6-workspacecreate_file)
- [构建与命令](#构建与命令)
  - [workspace.run_build](#7-workspacerun_build)
  - [workspace.run_test](#8-workspacerun_test)
  - [workspace.run_command](#9-workspacerun_command)
- [Cangjie 分析与 AST](#cangjie-分析与-ast)
  - [cangjie.analyze_file](#10-cangjieanalyze_file)
  - [cangjie.edit_ast_node](#11-cangjieedit_ast_node)
  - [cangjie.ast_parse](#12-cangjieast_parse)
  - [cangjie.ast_query_nodes](#13-cangjieast_query_nodes)
  - [cangjie.ast_list_nodes](#14-cangjieast_list_nodes)
- [Cangjie LSP 集成](#cangjie-lsp-集成)
  - [cangjie.lsp_status](#15-cangjielsp_status)
  - [cangjie.lsp_probe](#16-cangjielsp_probe)
  - [cangjie.lsp_document_symbols](#17-cangjielsp_document_symbols)
  - [cangjie.lsp_workspace_symbols](#18-cangjielsp_workspace_symbols)
  - [cangjie.lsp_definition](#19-cangjielsp_definition)
- [项目模板](#项目模板)
  - [project.list_examples](#20-projectlist_examples)
  - [project.bootstrap_json_parser](#21-projectbootstrap_json_parser)
- [事务回滚](#事务回滚)
  - [workspace.rollback](#22-workspacerollback)
- [客户端接入配置](#客户端接入配置)

---

## 概述

`service` 是 CangjieCoder 的底层工具服务，通过 **stdio MCP**（Model Context Protocol）或 **HTTP** 对外暴露 22 个工具。这些工具覆盖文件读写、文本搜索替换、构建测试、AST 解析与编辑、LSP 语义查询、技能检索、项目模板和事务回滚等能力。

**架构要点**：
- MCP 协议层在 `service/src/mcp/protocol.cj` 中定义工具元数据（名称、参数、描述）
- 工具处理函数在 `service/src/mcp_handlers.cj` 中实现，每个处理函数接收 `McpToolContext`（含 `workspaceRoot` 和 `serviceRoot`）和参数 `JsonObject`
- 所有涉及路径的工具通过 `ensureWorkspacePath()` 验证路径不会逃逸出仓库根目录
- 所有修改型操作通过 `FileBackupStore` 自动备份，支持 `workspace.rollback` 一键恢复
- 内置 AST 解析基于 `cangjie-tree-sitter` 动态库（tree-sitter 引擎的仓颉封装），无需外部工具即可工作

## 工具总览

| # | 工具名 | 类别 | 说明 |
|---|--------|------|------|
| 1 | `skills.search` | 技能 | 搜索内置仓颉技能语料 |
| 2 | `workspace.read_file` | 文件 | 读取仓库内文件内容 |
| 3 | `workspace.list_files` | 文件 | 递归列举仓库内文件 |
| 4 | `workspace.search_text` | 文件 | 在仓库文件中搜索文本 |
| 5 | `workspace.replace_text` | 文件 | 精确替换文件中唯一匹配的文本 |
| 6 | `workspace.create_file` | 文件 | 创建文件并自动建立父目录 |
| 7 | `workspace.run_build` | 命令 | 运行 `cjpm build` |
| 8 | `workspace.run_test` | 命令 | 运行 `cjpm test` |
| 9 | `workspace.run_command` | 命令 | 运行受限白名单命令 |
| 10 | `cangjie.analyze_file` | 分析 | 逐级分析仓颉源文件 |
| 11 | `cangjie.edit_ast_node` | AST | 通过 AST 节点类型定位并替换源码 |
| 12 | `cangjie.ast_parse` | AST | 内置 tree-sitter 解析，返回 S-expression |
| 13 | `cangjie.ast_query_nodes` | AST | 按节点类型查询 AST 节点 |
| 14 | `cangjie.ast_list_nodes` | AST | 列出命名 AST 节点概览 |
| 15 | `cangjie.lsp_status` | LSP | 检测 LSP 二进制是否可用 |
| 16 | `cangjie.lsp_probe` | LSP | 轻量 LSP 初始化探测 |
| 17 | `cangjie.lsp_document_symbols` | LSP | 查询文档符号 |
| 18 | `cangjie.lsp_workspace_symbols` | LSP | 查询工作区级符号 |
| 19 | `cangjie.lsp_definition` | LSP | 解析符号定义位置 |
| 20 | `project.list_examples` | 模板 | 列出可引导的示例项目 |
| 21 | `project.bootstrap_json_parser` | 模板 | 复制 JsonParser 示例到工作区 |
| 22 | `workspace.rollback` | 回滚 | 回滚所有文件修改 |

---

## 1. `skills.search`

**功能**：在 `.github/skills/` 目录中搜索内置的仓颉语言技能语料。技能以 `SKILL.md` 文件组织，包含名称、描述和预览内容。

**实现原理**：`SkillRegistry` 在初始化时扫描 `serviceRoot/.github/skills/` 目录，递归加载所有 `SKILL.md` 文件并解析其 YAML front matter（name、description）。搜索时对查询词做分词，然后按 id/name/description/preview 多级权重打分排序，返回前 N 个最佳匹配。

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `query` | string | ✅ | 搜索关键词 |

**请求示例**：
```json
{"method":"tools/call","params":{"name":"skills.search","arguments":{"query":"HTTP 服务器"}}}
```

---

## 工作区文件操作

### 2. `workspace.read_file`

**功能**：读取仓库根目录下的单个文件，返回文件路径、内容和字节数。

**实现原理**：通过 `ensureWorkspacePath()` 将相对路径解析为绝对路径并验证不超出仓库根目录，然后调用 `readTextFile()` 读取 UTF-8 内容。返回结构包含规范化后的相对路径、文件内容和字节数。

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | string | ✅ | 仓库相对路径或仓库内绝对路径 |

**请求示例**：
```json
{"method":"tools/call","params":{"name":"workspace.read_file","arguments":{"path":"src/main.cj"}}}
```

### 3. `workspace.list_files`

**功能**：递归列举仓库根目录（或指定子目录）下的文件，自动排除 `target/`、`.git/`、`node_modules/` 等构建产物目录。

**实现原理**：在指定的工作区子目录中执行 `find` 命令，过滤常见的构建产物和版本管理目录（通过 `-prune` 跳过），返回按字典序排列的文件路径列表。结果数量受 `limit` 参数限制。

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | string | | 子目录路径。默认为仓库根目录 |
| `limit` | integer | | 最大返回文件数。默认 200 |

**请求示例**：
```json
{"method":"tools/call","params":{"name":"workspace.list_files","arguments":{"path":"src","limit":50}}}
```

### 4. `workspace.search_text`

**功能**：在仓库文件中搜索精确文本匹配，返回文件路径、行号和匹配行预览。

**实现原理**：在工作区目录中执行 `grep -rn` 命令进行递归文本搜索，同时通过 `--exclude-dir` 排除构建产物目录。解析 grep 的 `文件:行号:内容` 输出格式，将结果结构化为 JSON 数组（每条包含 file、line、preview）。

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `query` | string | ✅ | 搜索文本 |
| `path` | string | | 搜索子目录。默认为仓库根目录 |
| `limit` | integer | | 最大匹配数。默认 20 |

**请求示例**：
```json
{"method":"tools/call","params":{"name":"workspace.search_text","arguments":{"query":"func main","path":"src"}}}
```

### 5. `workspace.replace_text`

**功能**：精确替换文件中唯一匹配的一处文本。为避免歧义替换，当 `oldText` 匹配多处时拒绝操作。

**实现原理**：读取目标文件全文，使用 `String.count()` 统计 `oldText` 出现次数。若恰好匹配 1 处，先通过 `globalBackupStore.backup()` 保存原始内容（支持后续 rollback），再执行 `String.replace()` 写回文件。匹配 0 处返回"未找到"，匹配 >1 处返回"歧义拒绝"。

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | string | ✅ | 文件路径 |
| `oldText` | string | ✅ | 要替换的精确文本 |
| `newText` | string | ✅ | 替换后的文本 |

**请求示例**：
```json
{"method":"tools/call","params":{"name":"workspace.replace_text","arguments":{"path":"src/main.cj","oldText":"println(\"hello\")","newText":"println(\"world\")"}}}
```

### 6. `workspace.create_file`

**功能**：在仓库中创建文件，自动建立缺失的父目录。默认拒绝覆盖已有文件，可通过 `overwrite` 参数允许覆盖。

**实现原理**：通过 `ensurePlannedWorkspacePath()` 验证目标路径在仓库根目录内（即使部分父目录尚不存在也能正确验证），然后递归创建父目录。当 `overwrite=true` 且文件已存在时，先通过 `globalBackupStore.backup()` 保存原始内容。最后将内容写入目标文件。

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | string | ✅ | 文件路径 |
| `content` | string | | 文件内容。默认为空文件 |
| `overwrite` | boolean | | 是否允许覆盖。默认 false |

**请求示例**：
```json
{"method":"tools/call","params":{"name":"workspace.create_file","arguments":{"path":"src/utils/helper.cj","content":"package utils\n\nfunc hello(): String { \"Hello\" }\n"}}}
```

---

## 构建与命令

### 7. `workspace.run_build`

**功能**：在工作区（或指定子目录）中执行 `cjpm build`，返回退出码、stdout 和 stderr。

**实现原理**：将命令固定为 `cjpm`，参数固定为 `["build"]`，通过 `workspaceRunCommandJson()` 在指定目录中启动子进程。捕获标准输出和标准错误，格式化为包含 command、arguments、exitCode、stdout、stderr 的结构化结果。

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | string | | 工作目录子路径。默认为仓库根目录 |

**请求示例**：
```json
{"method":"tools/call","params":{"name":"workspace.run_build","arguments":{}}}
```

### 8. `workspace.run_test`

**功能**：在工作区中执行 `cjpm test`，返回退出码、stdout 和 stderr。

**实现原理**：与 `run_build` 相同，命令固定为 `cjpm`，参数固定为 `["test"]`。

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | string | | 工作目录子路径。默认为仓库根目录 |

**请求示例**：
```json
{"method":"tools/call","params":{"name":"workspace.run_test","arguments":{"path":"service"}}}
```

### 9. `workspace.run_command`

**功能**：运行受限白名单命令（`cjpm`、`cjc`、`cjlint`、`tree-sitter`、`grep`、`find`），用于 Agent 自动化场景。

**实现原理**：通过 `isAllowedWorkspaceCommand()` 验证命令是否在白名单中（防止任意命令注入），然后在工作区目录中启动子进程执行。白名单包含仓颉工具链和安全的搜索命令。返回结构化结果含退出码和输出内容。

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `command` | string | ✅ | 命令名（必须在白名单中） |
| `args` | array | | 命令参数数组 |
| `path` | string | | 工作目录子路径 |

**请求示例**：
```json
{"method":"tools/call","params":{"name":"workspace.run_command","arguments":{"command":"grep","args":["-rn","TODO","src/"],"path":"service"}}}
```

---

## Cangjie 分析与 AST

### 10. `cangjie.analyze_file`

**功能**：对仓颉源文件运行逐级分析（tree-sitter → cjlint → cjc），返回最佳可用诊断。

**实现原理**：`analyzeCangjieFile()` 按优先级依次尝试三个外部分析器：
1. **tree-sitter**（通过 `$TREE_SITTER_CANGJIE` 环境变量指定，默认 `tree-sitter`）：运行 `tree-sitter parse <file>`，成功则返回语法树
2. **cjlint**（通过 `$CJLINT_COMMAND` 环境变量指定，默认 `cjlint`）：运行静态分析
3. **cjc**（通过 `$CJC_COMMAND` 环境变量指定，默认 `cjc`）：运行编译器语法检查

返回第一个成功的分析结果，或报告所有分析器均不可用。

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | string | ✅ | 仓颉源文件路径 |

**请求示例**：
```json
{"method":"tools/call","params":{"name":"cangjie.analyze_file","arguments":{"path":"src/main.cj"}}}
```

### 11. `cangjie.edit_ast_node`

**功能**：通过 tree-sitter 节点类型定位 AST 节点，并将其源码替换为新内容。支持多节点场景下通过 index 选择目标节点。

**实现原理**：
1. 调用外部 `tree-sitter parse <file>` 获取 AST 文本输出（需配置 `$TREE_SITTER_CANGJIE`）
2. `parseTreeSitterNodeMatches()` 从输出中解析 `nodeType [行, 列] - [行, 列]` 格式的坐标
3. 按 index 选择目标节点，通过 `offsetForPoint()` 将行列坐标转换为字节偏移
4. 在编辑前通过 `globalBackupStore.backup()` 保存原始文件（支持 rollback）
5. 按字节偏移切割原始文件并插入 replacement 文本

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | string | ✅ | 仓颉源文件路径 |
| `nodeType` | string | ✅ | tree-sitter 节点类型（如 `functionDefinition`） |
| `replacement` | string | ✅ | 替换源码 |
| `index` | integer | | 匹配索引。默认 0（第一个匹配） |

**请求示例**：
```json
{"method":"tools/call","params":{"name":"cangjie.edit_ast_node","arguments":{"path":"src/main.cj","nodeType":"functionDefinition","replacement":"func hello(): String { \"world\" }","index":0}}}
```

### 12. `cangjie.ast_parse`

**功能**：使用内置 tree-sitter 引擎解析仓颉源码，返回完整的 S-expression 语法树。无需外部 tree-sitter CLI。

**实现原理**：
1. 读取源文件内容
2. 调用 `treeSitterParseSexp()` —— 这是 `service/src/ast/ast.cj` 中的薄代理，委托给 `cangjie-tree-sitter` 库的 `parseSexp()`
3. 库内部通过 C FFI 调用 tree-sitter 引擎：`ts_parser_new()` → `ts_parser_set_language(tree_sitter_cangjie())` → `ts_parser_parse_string()` → `ts_node_string(root)` 获取 S-expression
4. 内存管理：`acquireArrayRawData()`/`releaseArrayRawData()` 传递源码字节，`free()` 释放 `ts_node_string()` 返回的 C 字符串
5. 返回包含文件路径和 sexp 字符串的结构化结果

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | string | ✅ | 仓颉源文件路径 |

**请求示例**：
```json
{"method":"tools/call","params":{"name":"cangjie.ast_parse","arguments":{"path":"src/main.cj"}}}
```

**响应示例**：
```json
{
  "ok": true,
  "summary": "AST parse completed",
  "data": {
    "path": "src/main.cj",
    "sexp": "(translationUnit (mainDefinition (block (expressionStatement ...))))"
  }
}
```

### 13. `cangjie.ast_query_nodes`

**功能**：查询源文件中所有匹配指定类型的 AST 节点，返回每个节点的类型、位置（行列）、字节偏移和子节点数。

**实现原理**：
1. 读取源文件并调用 `treeSitterQueryNodes(source, nodeType)` —— 委托给 `cangjie-tree-sitter` 库的 `queryNodes()`
2. 库内部解析源码后，从根节点开始递归遍历整棵 AST 树（`collectNodesByType()`）
3. 对每个节点调用 `ts_node_type()` 比较类型名，匹配时通过 `extractNodeInfo()` 提取完整元信息：
   - `ts_node_start_point()`/`ts_node_end_point()` → 行列坐标
   - `ts_node_start_byte()`/`ts_node_end_byte()` → 字节偏移
   - `ts_node_is_named()` → 是否为命名节点
   - `ts_node_child_count()` → 子节点数
4. 返回结构包含匹配数和节点信息 JSON 数组

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | string | ✅ | 仓颉源文件路径 |
| `nodeType` | string | ✅ | tree-sitter 节点类型（如 `functionDefinition`、`classDefinition`） |

**请求示例**：
```json
{"method":"tools/call","params":{"name":"cangjie.ast_query_nodes","arguments":{"path":"src/main.cj","nodeType":"functionDefinition"}}}
```

**响应示例**：
```json
{
  "ok": true,
  "summary": "Found 2 node(s) of type functionDefinition",
  "data": {
    "path": "src/main.cj",
    "nodeType": "functionDefinition",
    "matchCount": 2,
    "nodes": [
      {"type":"functionDefinition","startRow":0,"startColumn":0,"endRow":2,"endColumn":1,"startByte":0,"endByte":42,"isNamed":true,"childCount":4},
      {"type":"functionDefinition","startRow":4,"startColumn":0,"endRow":6,"endColumn":1,"startByte":44,"endByte":86,"isNamed":true,"childCount":4}
    ]
  }
}
```

### 14. `cangjie.ast_list_nodes`

**功能**：列出源文件中所有命名 AST 节点的概览，支持限制遍历深度避免输出过大。

**实现原理**：
1. 读取源文件并调用 `treeSitterListNamedNodes(source, maxDepth)` —— 委托给 `cangjie-tree-sitter` 库的 `listNamedNodes()`
2. 库内部从根节点递归遍历（`collectNamedNodes()`），仅收集 `ts_node_is_named()` 返回 true 的节点
3. 当递归深度超过 `maxDepth` 时停止下探，避免大文件产生过多输出
4. 返回节点信息 JSON 数组

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | string | ✅ | 仓颉源文件路径 |
| `maxDepth` | integer | | 最大遍历深度。默认 4 |

**请求示例**：
```json
{"method":"tools/call","params":{"name":"cangjie.ast_list_nodes","arguments":{"path":"src/main.cj","maxDepth":3}}}
```

---

## Cangjie LSP 集成

以下工具依赖外部 Cangjie LSP 服务器二进制。通过环境变量 `$CANGJIE_LSP_COMMAND` 指定路径，或自动在 `$CANGJIE_SDK_HOME/bin/` 和 `$PATH` 中搜索 `LSPServer`。

LSP 连接使用**持久化长连接**模式：`LspSessionManager` 维护一个全局长驻 LSP 子进程，首次使用时完成 `initialize` 握手，后续查询复用该进程。当会话异常时自动回退到冷启动模式保证可用性。

### 15. `cangjie.lsp_status`

**功能**：检查 Cangjie LSP 二进制是否已配置或可发现。不启动 LSP 进程。

**实现原理**：`inspectLspStatus()` 按优先级检查：
1. `$CANGJIE_LSP_COMMAND` 环境变量
2. `$CANGJIE_SDK_HOME/bin/LSPServer` 路径
3. 系统 `$PATH` 中的 `LSPServer`

返回发现的 LSP 二进制路径和检查方法。

**参数**：无

**请求示例**：
```json
{"method":"tools/call","params":{"name":"cangjie.lsp_status","arguments":{}}}
```

### 16. `cangjie.lsp_probe`

**功能**：对 LSP 服务器执行轻量的 `initialize` → `shutdown` 探测，验证 LSP 二进制是否可正常启动和响应。

**实现原理**：`probeLspServer()` 启动 LSP 进程，发送 `initialize` 请求和 `initialized` 通知，等待 `initialize` 响应，然后发送 `shutdown` 和 `exit` 关闭进程。通过 `isSuccessfulInitializeResponse()` 验证响应是否包含 `capabilities` 字段。

**参数**：无

**请求示例**：
```json
{"method":"tools/call","params":{"name":"cangjie.lsp_probe","arguments":{}}}
```

### 17. `cangjie.lsp_document_symbols`

**功能**：查询指定源文件中的文档符号（函数、类、变量等）。

**实现原理**：向 LSP 服务器发送 `textDocument/documentSymbol` 请求。在发送查询前先通过 `textDocument/didOpen` 通知告知 LSP 服务器文件内容。优先使用持久化长连接，失败时回退到冷启动模式。

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | string | ✅ | 仓颉源文件路径 |

**请求示例**：
```json
{"method":"tools/call","params":{"name":"cangjie.lsp_document_symbols","arguments":{"path":"src/main.cj"}}}
```

### 18. `cangjie.lsp_workspace_symbols`

**功能**：在整个工作区中搜索符号名称。

**实现原理**：向 LSP 服务器发送 `workspace/symbol` 请求，传入查询字符串。空字符串请求广泛的符号扫描。

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `query` | string | | 符号名或模糊查询。空字符串表示广泛扫描 |

**请求示例**：
```json
{"method":"tools/call","params":{"name":"cangjie.lsp_workspace_symbols","arguments":{"query":"Config"}}}
```

### 19. `cangjie.lsp_definition`

**功能**：解析源码中指定位置的符号定义位置。

**实现原理**：向 LSP 服务器发送 `textDocument/definition` 请求，传入文件 URI 和零基行列坐标。在请求前先通过 `textDocument/didOpen` 通知打开文件。

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | string | ✅ | 仓颉源文件路径 |
| `line` | integer | ✅ | 零基行号 |
| `column` | integer | ✅ | 零基列号 |

**请求示例**：
```json
{"method":"tools/call","params":{"name":"cangjie.lsp_definition","arguments":{"path":"src/main.cj","line":5,"column":10}}}
```

---

## 项目模板

### 20. `project.list_examples`

**功能**：列出可引导到工作区的内置仓颉示例项目。

**实现原理**：`listExampleProjects()` 返回硬编码的示例项目列表（当前包含 `json_parser`），每个项目包含 id、名称、描述和模板路径。模板文件存放在 `examples/` 目录中。

**参数**：无

**请求示例**：
```json
{"method":"tools/call","params":{"name":"project.list_examples","arguments":{}}}
```

### 21. `project.bootstrap_json_parser`

**功能**：将内置的 JsonParser 示例项目复制到工作区指定路径，自动创建父目录。

**实现原理**：`bootstrapJsonParserProject()` 验证目标路径在仓库内且不已存在，然后递归复制模板目录（`examples/json_parser`）到目标路径，并清理复制过来的 `target/` 和 `cjpm.lock` 文件。

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | string | ✅ | 工作区内的目标目录 |

**请求示例**：
```json
{"method":"tools/call","params":{"name":"project.bootstrap_json_parser","arguments":{"path":"demo/json-parser"}}}
```

---

## 事务回滚

### 22. `workspace.rollback`

**功能**：将所有被修改的文件回滚到编辑操作前的状态。

**实现原理**：`FileBackupStore` 是一个全局的文件备份存储。以下操作会在修改文件前自动调用 `backup(path)` 保存原始内容：
- `workspace.replace_text` —— 文本替换前备份
- `workspace.create_file`（overwrite 模式）—— 覆盖前备份
- `cangjie.edit_ast_node` —— AST 编辑前备份

`workspace.rollback` 调用 `rollbackAll()` 将所有已备份文件恢复到首次修改前的状态（同一文件只保存首次备份），然后清空备份记录。返回恢复的文件列表和数量。

**参数**：无

**请求示例**：
```json
{"method":"tools/call","params":{"name":"workspace.rollback","arguments":{}}}
```

---

## 客户端接入配置

### 前置条件

```bash
export CANGJIE_SDK_HOME=/path/to/cangjie-sdk
source "${CANGJIE_SDK_HOME}/envsetup.sh"
export STDX_PATH=/path/to/cangjie-stdx/linux_x86_64_cjnative/dynamic/stdx
```

建议先构建一遍 `service`：

```bash
cd cangjie-tree-sitter/treesitter && make && cd ../..
cd service && cjpm build && cd ..
```

以下示例统一假设仓库位于 `/absolute/path/to/CangjieCoder`，要操作的目标仓库位于 `/absolute/path/to/workspace`。

### 推荐命令

优先使用已构建二进制：

```bash
/absolute/path/to/CangjieCoder/service/target/release/bin/main mcp-stdio --repo /absolute/path/to/workspace
```

如果你更希望每次由 `cjpm` 负责启动，也可以改成：

```bash
cjpm run --run-args "mcp-stdio --repo /absolute/path/to/workspace"
```

### VS Code

根据 VS Code MCP 文档，工作区可放在 `.vscode/mcp.json`：

```json
{
  "servers": {
    "cangjiecoder-service": {
      "type": "stdio",
      "command": "/absolute/path/to/CangjieCoder/service/target/release/bin/main",
      "args": [
        "mcp-stdio",
        "--repo",
        "/absolute/path/to/workspace"
      ],
      "env": {
        "CANGJIE_SDK_HOME": "/path/to/cangjie-sdk",
        "STDX_PATH": "/path/to/cangjie-stdx/linux_x86_64_cjnative/dynamic/stdx"
      }
    }
  }
}
```

### Cursor

Cursor 常用 `~/.cursor/mcp.json` 或项目内 `.cursor/mcp.json`：

```json
{
  "mcpServers": {
    "cangjiecoder-service": {
      "command": "/absolute/path/to/CangjieCoder/service/target/release/bin/main",
      "args": [
        "mcp-stdio",
        "--repo",
        "/absolute/path/to/workspace"
      ],
      "env": {
        "CANGJIE_SDK_HOME": "/path/to/cangjie-sdk",
        "STDX_PATH": "/path/to/cangjie-stdx/linux_x86_64_cjnative/dynamic/stdx"
      }
    }
  }
}
```

### OpenCode

OpenCode 的本地 MCP 示例可写成：

```json
{
  "mcp": {
    "cangjiecoder-service": {
      "type": "local",
      "command": [
        "/absolute/path/to/CangjieCoder/service/target/release/bin/main",
        "mcp-stdio",
        "--repo",
        "/absolute/path/to/workspace"
      ],
      "enabled": true,
      "env": {
        "CANGJIE_SDK_HOME": "/path/to/cangjie-sdk",
        "STDX_PATH": "/path/to/cangjie-stdx/linux_x86_64_cjnative/dynamic/stdx"
      }
    }
  }
}
```

### 调试建议

- 先在终端手工运行 `service` 的 `mcp-stdio`，确认可以正常启动
- 优先使用绝对路径
- 模型密钥只需要配置给 `agent`，不要配置到 `service` 或写入仓库
- 内置 AST 解析（`cangjie.ast_parse`、`cangjie.ast_query_nodes`、`cangjie.ast_list_nodes`）无需额外配置即可工作
- 如果需要使用外部分析器或 AST 编辑功能，可配置：

```bash
export TREE_SITTER_CANGJIE=tree-sitter
export CJLINT_COMMAND=cjlint
export CANGJIE_LSP_COMMAND=/path/to/LSPServer
```

> VS Code / Cursor / OpenCode 的 MCP 配置格式会演进，以上示例基于当前公开文档整理，若客户端版本变更，请以各自最新文档为准。
