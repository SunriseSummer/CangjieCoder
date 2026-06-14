package cangjiecoder

import std.argopt.*
import cangjiecoder.app.*
import cangjiecoder.httpx.setTlsOptions

/**
 * 入口：解析命令行参数，bootstrap 装配上下文，再进入 REPL
 *
 * 命令行选项：
 *   --insecure-tls    禁用 TLS 证书校验（TrustAll，仅用于调试）
 *   --ca-bundle=PATH  自定义 CA PEM bundle 文件路径
 *   --tls-debug       打印 CA 加载数量等 TLS 调试信息
 *
 * 退出码：
 *   0  正常退出
 *   1  初始化失败（如未配置 API Key 且用户取消引导）
 */
main(args: Array<String>): Int64 {
    let specs = [
        Long("insecure-tls", NoValue),
        Long("ca-bundle", RequiredValue),
        Long("tls-debug", NoValue)
    ]

    var parsed: ParsedArguments
    try {
        parsed = parseArguments(args, specs)
    } catch (e: ArgumentParseException) {
        eprintln("参数错误：${e}")
        eprintln("用法：cangjiecoder [--insecure-tls] [--ca-bundle=PATH] [--tls-debug]")
        return 1
    }

    let insecure = parsed.options.contains("insecure-tls")
    let caBundle = parsed.options.get("ca-bundle") ?? ""
    let tlsDebug = parsed.options.contains("tls-debug")

    setTlsOptions(insecure: insecure, caBundle: caBundle, tlsDebug: tlsDebug)

    if (insecure) {
        eprintln("[TLS] 警告：--insecure-tls 已启用，TLS 证书校验已禁用（仅用于调试）")
    }

    match (bootstrap()) {
        case Some(ctx) => return runRepl(ctx)
        case None => return 1
    }
}
