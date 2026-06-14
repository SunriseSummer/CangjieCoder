# Cangjie Coder · 端到端测试

基于 Python 子进程驱动编译后的 cangjiecoder 二进制做黑盒行为测试，作为 `cjpm test` 单元测试之上的端到端保障。

## 框架原理

### 架构

```
┌───────────────────────────────────────────────────────┐
│                     run_all.py                        │
│       统一入口 · CLI 参数 · 用例发现 · 日志对比        │
└─────────────────────────┬─────────────────────────────┘
                          │ 按 TEST_MODULES 顺序逐个运行
                          ▼
┌───────────────────────────────────────────────────────┐
│                     driver.py                         │
│                                                       │
│  Sandbox           隔离 HOME 沙箱，测试后自动清理      │
│  CoderProc         子进程封装 + 后台 drain 防死锁      │
│  MockServer        本地 mock OpenAI 服务端（纯 stdlib）│
│  connect_provider  /connect + /model 端到端配置       │
└───────────────────────────────────────────────────────┘
                          │
                 ┌────────┴────────┐
                 ▼                 ▼
           mock 用例          实战用例
         (本地 mock)       (真实服务商)
```

### 核心组件

| 组件 | 职责 |
| --- | --- |
| `Sandbox` | 为每个测试创建隔离 HOME 目录（含 `.agents/cangjiecoder/config.json`），测试结束自动清理 |
| `CoderProc` | 启动 cangjiecoder 子进程，后台线程持续 drain stdout/stderr 防死锁，提供 `send()`、`wait_for()`、`wait_for_any()` 同步交互 API |
| `MockServer` | 零依赖的本地 OpenAI Chat Completions 模拟服务端，支持脚本化 tool-call 响应编排 |
| `connect_provider()` | 通过 coder 的 `/connect` 和 `/model` 命令完成端到端服务商配置，不直接写入 endpoint 地址 |
| `run_all.py` | 统一入口，动态导入 `TEST_MODULES` 中注册的用例模块，按 TAGS 过滤（mock / live），保存日志并与历史对比检测退化 |

### 测试用例协议

每个测试用例是一个 Python 包（`e2etest/<name>/__init__.py`），导出三个成员：

```python
NAME = "bug_fix"            # 显示名称
TAGS = ["live"]             # 分类标签：mock / live
def run(**kwargs):          # 执行入口
    # kwargs 包含 provider、model（仅 live）
    return (passed, stdout, stderr, error_msg)
```

`run()` 返回四元组：`(passed: bool, stdout: str, stderr: str, error_msg: str)`。框架据此判定结果、保存日志、执行退化对比。

### 服务商配置机制

测试不直接写入服务商 endpoint 地址，而是通过 coder 自身的命令完成配置：

1. `write_bootstrap_config()` — 将环境变量中的 API Key 写入沙箱配置，设置 `currentProvider`
2. `connect_provider()` — 发送 `/connect <provider>` 和 `/model <model>` 命令，由 coder 内部注册表解析 endpoint

这确保了端到端测试覆盖 coder 的服务商连接流程本身，而非绕过它。

### 日志与退化检测

每次运行保存完整 CLI 日志到用例子目录（`YYYYMMDD_HHMMSS.log`），框架自动与上次日志对比以下指标：

- `[tool-call]` 和 `[final]` 出现次数（迭代效率）
- 错误关键词频率（`error`、`traceback`、`failed`）
- 通过/失败状态变化

## 目录结构

```
e2etest/
├── driver.py                 通用驱动：沙箱、子进程封装、mock 服务端、provider 配置
├── log_utils.py              日志保存与退化对比检测
├── run_all.py                统一入口（--provider/--model/--skip/--only）
├── clean_logs.py             一键清理日志
│
├── help_exit/                mock: /help + /exit 启动退出
├── agent_write/              mock: agent 模式 write_file 工具调用
├── diff_undo/                mock: /diff + /undo 命令
├── compact/                  mock: /compact 历史压缩
├── create_project/           实战: 多文件新项目创建
├── bug_fix/                  实战: edit_file 修复 Python 代码 bug
├── lru_cache/                实战: LRU Cache 多 bug 修复
│
├── test_mock_agent.py        mock 核心用例（unittest）
├── test_kimi_smoke.py        Moonshot 烟雾测试
├── test_huawei_smoke.py      华为云 MaaS 烟雾测试
├── test_zhipu_smoke.py       智谱 GLM 烟雾测试
└── test_deepseek_smoke.py    DeepSeek 烟雾测试
```

## 准备

1. 安装 Cangjie SDK 1.0.5（参见 `coder/Readme.md`）
2. 构建：

   ```bash
   cd coder
   cjpm build
   ```

3. 设置 stdx 动态库路径：

   ```bash
   source /opt/cangjie/envsetup.sh
   export LD_LIBRARY_PATH=/opt/cangjie/linux_x86_64_cjnative/dynamic/stdx:$LD_LIBRARY_PATH
   ```

## 运行

### 全量测试

```bash
cd coder
python3 e2etest/run_all.py                              # mock + 实战（默认 Moonshot）
python3 e2etest/run_all.py --mock-only                   # 仅 mock（无需网络）
python3 e2etest/run_all.py --provider zhipu              # 指定服务商（使用默认模型）
python3 e2etest/run_all.py --provider deepseek --model deepseek-v4-pro  # 指定服务商和模型
python3 e2etest/run_all.py --only bug_fix                # 仅运行指定场景
python3 e2etest/run_all.py --skip lru_cache              # 跳过指定场景
```

### 烟雾测试

```bash
python3 -m unittest -v e2etest.test_huawei_smoke     # 华为云 MaaS
python3 -m unittest -v e2etest.test_zhipu_smoke      # 智谱 GLM
python3 -m unittest -v e2etest.test_deepseek_smoke   # DeepSeek
python3 -m unittest -v e2etest.test_kimi_smoke       # Moonshot
```

烟雾测试通过环境变量 + DNS 可达性检查自动门控——无凭据或网络不可达时自动跳过。

### 日志管理

每个测试用例的 CLI 日志保存到对应子目录，命名格式 `YYYYMMDD_HHMMSS.log`。运行结束自动与上次日志对比，检查是否有退化。

```bash
python3 e2etest/clean_logs.py           # 查看待清理日志
python3 e2etest/clean_logs.py --force   # 执行清理
```

## 多服务商配置

`run_all.py` 通过 `--provider` 和 `--model` 参数在框架层面切换服务商，作用于所有实战测试用例（mock 测试不受影响）。测试内部通过 coder 的 `/connect` 和 `/model` 命令完成端到端服务商配置。

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `--provider` | 服务商 ID | `kimi` |
| `--model` | 模型 ID | 取服务商默认模型 |

### 环境变量

| 服务商 | 环境变量 | 默认模型 |
| --- | --- | --- |
| 华为云 MaaS | `HUAWEI_API_KEY` | kimi-k2.6 |
| Moonshot | `KIMI_API_KEY` | kimi-k2.6 |
| 智谱 GLM | `ZHIPU_API_KEY` | glm-5.1 |
| DeepSeek | `DEEPSEEK_API_KEY` | deepseek-v4-pro |

### 示例

```bash
# 智谱 GLM 5.1
export ZHIPU_API_KEY="..."
python3 e2etest/run_all.py --provider zhipu

# DeepSeek V4 Pro
export DEEPSEEK_API_KEY="..."
python3 e2etest/run_all.py --provider deepseek

# 华为云 Kimi K2.6
export HUAWEI_API_KEY="..."
python3 e2etest/run_all.py --provider huawei --model kimi-k2.6
```

## Mock 测试用例

预期 7 个用例全部通过：

| 用例 | 验证点 |
| --- | --- |
| `test_help_then_exit` | `/help` 输出包含 `/diff`、`/undo`、`/compact` |
| `test_status_shows_journal_zero` | `/status` 报告 `文件改动: 0 次` |
| `test_chat_plain_text_reply` | chat 模式流式接口正常 |
| `test_agent_writes_file_through_tool_call` | `write_file` 工具调用落盘 |
| `test_diff_and_undo_after_write` | `/diff` + `/undo` 端到端 |
| `test_undo_restores_previous_content` | `edit_file` 后 `/undo` 恢复原内容 |
| `test_compact_shortens_history` | `/compact` 报告「历史已压缩」 |

## 已知问题

### 瞬态错误自动重试

`agent/loop.cj::sendWithRetry` 对以下瞬态错误自动重试一次（间隔 1 秒）：

- `Invalid utf8 byte sequence`（stdx chunked 解码 CJK 断字）
- `connection reset` / `EOF`
- `read timeout` / `write timeout`

永久性错误（HTTP 4xx / 鉴权失败 / TLS 配置错误）不触发重试。

### TLS 配置

早期版本在部分域名（`api.moonshot.cn`、`api.deepseek.com`）上存在 TLS 握手失败的问题，原因是 stdx HTTP Client 未自动从 URL 提取 hostname 发送 TLS SNI 扩展。当前版本已通过在 `buildHttpClient` 中显式设置 `tls.domain`（SNI）修复，所有内建服务商（华为云、Moonshot、DeepSeek、智谱）均可正常连接，**无需**设置 `CANGJIECODER_INSECURE_TLS`。

如遇特殊网络环境仍需调试，可使用以下命令行选项：

```bash
target/release/bin/main --insecure-tls        # 禁用 TLS 证书校验（仅限调试/内网）
target/release/bin/main --ca-bundle=/path/to/ca.pem   # 自定义 PEM CA bundle
target/release/bin/main --tls-debug                    # 打印 CA 加载数量
```
