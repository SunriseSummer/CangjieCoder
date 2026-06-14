package cangjiecoder.httpx

import std.collection.*
import std.env.*
import std.fs.*
import std.process.*
import stdx.crypto.x509.*
import stdx.net.tls.*

/**
 * TLS 与 CA 证书策略
 *
 * stdx 默认证书校验不会稳定加载系统 CA
 * 这里统一注入 CustomCA 并保留 --insecure-tls、--ca-bundle、--tls-debug 配置入口
 */
struct TlsConfig {
    var insecure: Bool
    var caBundle: String
    var debug: Bool

    init(insecure!: Bool = false, caBundle!: String = "", debug!: Bool = false) {
        this.insecure = insecure
        this.caBundle = caBundle
        this.debug = debug
    }
}

var globalTlsConfig = TlsConfig()
var insecureTlsWarned: Bool = false

public func setTlsOptions(insecure!: Bool = false, caBundle!: String = "", tlsDebug!: Bool = false): Unit {
    globalTlsConfig = TlsConfig(insecure: insecure, caBundle: caBundle, debug: tlsDebug)
}

@When[os != "Windows"]
let SYSTEM_CA_PATHS: Array<String> = [
    "/etc/ssl/certs/ca-certificates.crt", // Debian/Ubuntu/Alpine
    "/etc/pki/tls/certs/ca-bundle.crt", // RHEL/CentOS/Fedora
    "/etc/ssl/ca-bundle.pem", // SUSE
    "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem", // RHEL 新版
    "/etc/ssl/cert.pem" // BSD/macOS-style
]
@When[os == "Windows"]
let SYSTEM_CA_PATHS: Array<String> = [
    "C:/Program Files/Git/mingw64/ssl/certs/ca-bundle.crt",
    "C:/Program Files/Git/usr/ssl/certs/ca-bundle.crt",
    "C:/Program Files/Git/mingw64/etc/ssl/certs/ca-bundle.crt",
    "C:/Program Files (x86)/Git/mingw64/ssl/certs/ca-bundle.crt"
]

func buildTlsConfig(endpoint: String): TlsClientConfig {
    var tls = TlsClientConfig()
    if (!endpoint.isEmpty()) {
        let host = extractHost(endpoint)
        if (!host.isEmpty()) {
            tls.domain = host
        }
    }
    tls.verifyMode = resolveVerifyMode()
    return tls
}

func resolveVerifyMode(): CertificateVerifyMode {
    if (isInsecureTls()) {
        warnInsecureTlsOnce()
        return TrustAll
    }
    match (loadSystemCaCertificates()) {
        case Some(certs) =>
            applyCaEnvIfPossible()
            if (debugTls()) {
                eprintln("[TLS] loaded ${certs.size} CA certs from system bundle")
            }
            return CustomCA(certs)
        case None =>
            if (debugTls()) {
                eprintln("[TLS] no system CA bundle found; falling back to Default")
            }
            return Default
    }
}

func warnInsecureTlsOnce(): Unit {
    if (insecureTlsWarned) {
        return
    }
    eprintln("[警告] 已通过 --insecure-tls 启用 TrustAll；" +
        "TLS 证书校验已禁用，仅供调试，请勿用于生产。")
    insecureTlsWarned = true
}

func loadSystemCaCertificates(): ?Array<X509Certificate> {
    let paths = configuredCaPaths()
    for (path in paths) {
        if (!exists(path)) {
            continue
        }
        let pem = readPemFile(path) ?? continue
        if (pem.isEmpty()) {
            continue
        }
        match (decodeCaBundle(pem)) {
            case Some(certs) => return Some(certs)
            case None => continue
        }
    }
    return platformCaFallback()
}

func configuredCaPaths(): ArrayList<String> {
    var paths = ArrayList<String>()
    if (!globalTlsConfig.caBundle.isEmpty()) {
        paths.add(globalTlsConfig.caBundle)
    }
    for (caPath in SYSTEM_CA_PATHS) {
        paths.add(caPath)
    }
    return paths
}

func decodeCaBundle(pem: String): ?Array<X509Certificate> {
    try {
        let certs = X509Certificate.decodeFromPem(pem)
        if (certs.size == 0) {
            return None
        }
        return Some(Array<X509Certificate>(certs.size, {i => certs[i]}))
    } catch (_: Exception) {
        return None
    }
}

@When[os != "Windows"]
func platformCaFallback(): ?Array<X509Certificate> {
    return None
}

@When[os == "Windows"]
func platformCaFallback(): ?Array<X509Certificate> {
    match (loadWindowsCaFromCache()) {
        case Some(certs) => return Some(certs)
        case None => ()
    }

    let pem = exportWindowsTrustStore() ?? return None
    if (pem.isEmpty()) {
        return None
    }
    let certs = decodeCertsLenient(pem)
    if (certs.size == 0) {
        return None
    }
    cacheWindowsCaBundle(pem)
    if (debugTls()) {
        eprintln("[TLS] exported ${certs.size} CA certs from Windows cert store")
    }
    return Some(certs)
}

@When[os == "Windows"]
func loadWindowsCaFromCache(): ?Array<X509Certificate> {
    match (windowsCaCachePath()) {
        case Some(cache) where exists(cache) =>
            let cached = readPemFile(cache.toString()) ?? ""
            if (cached.isEmpty()) {
                return None
            }
            let certs = decodeCertsLenient(cached)
            if (certs.size == 0) {
                return None
            }
            if (debugTls()) {
                eprintln("[TLS] loaded ${certs.size} CA certs from cache")
            }
            return Some(certs)
        case _ => return None
    }
}

@When[os == "Windows"]
func cacheWindowsCaBundle(pem: String): Unit {
    match (windowsCaCachePath()) {
        case Some(cache) => try {
            File.writeTo(cache, pem.toArray())
        } catch (_: Exception) {
            ()
        }
        case None => ()
    }
}

@When[os == "Windows"]
func windowsCaCachePath(): ?Path {
    let tempDir = getVariable("TEMP") ?? (getVariable("TMP") ?? "")
    if (tempDir.isEmpty()) {
        return None
    }
    return Some(Path(tempDir).join("cangjiecoder-win-ca.pem"))
}

@When[os == "Windows"]
func exportWindowsTrustStore(): ?String {
    let script = "$ErrorActionPreference='SilentlyContinue';" +
        "foreach($s in 'Cert:\\LocalMachine\\Root','Cert:\\CurrentUser\\Root'," +
        "'Cert:\\LocalMachine\\CA','Cert:\\CurrentUser\\CA'){" + "Get-ChildItem $s | ForEach-Object {" +
        "'-----BEGIN CERTIFICATE-----';" + "[Convert]::ToBase64String($_.RawData,'InsertLineBreaks');" +
        "'-----END CERTIFICATE-----'}}"
    try {
        let proc = launch("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", script],
            stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
        let (code, stdoutBytes, _) = proc.waitOutput()
        if (code != 0) {
            return None
        }
        let text = String.fromUtf8(stdoutBytes)
        if (text.isEmpty()) {
            return None
        }
        return Some(text)
    } catch (_: Exception) {
        return None
    }
}

@When[os == "Windows"]
func decodeCertsLenient(pem: String): Array<X509Certificate> {
    let result = ArrayList<X509Certificate>()
    let endMarker = "-----END CERTIFICATE-----"
    var rest = pem
    while (true) {
        match (rest.indexOf(endMarker)) {
            case Some(idx) =>
                let block = rest[..(idx + endMarker.size)]
                rest = rest[(idx + endMarker.size)..]
                try {
                    let certs = X509Certificate.decodeFromPem(block)
                    for (c in certs) {
                        result.add(c)
                    }
                } catch (_: Exception) {
                    ()
                }
            case None => break
        }
    }
    return Array<X509Certificate>(result.size, {i => result[i]})
}

func readPemFile(path: String): ?String {
    try {
        Some(String.fromUtf8(File.readFrom(Path(path))))
    } catch (_: Exception) {
        None
    }
}

func applyCaEnvIfPossible(): Unit {
    match (getVariable("SSL_CERT_FILE")) {
        case Some(_) => return
        case None => ()
    }
    for (caPath in SYSTEM_CA_PATHS) {
        if (exists(caPath)) {
            try {
                setVariable("SSL_CERT_FILE", caPath)
            } catch (_: Exception) {
                ()
            }
            return
        }
    }
}

func isInsecureTls(): Bool {
    return globalTlsConfig.insecure
}

func debugTls(): Bool {
    return globalTlsConfig.debug
}

func extractHost(url: String): String {
    var host = url
    match (host.indexOf("://")) {
        case Some(schemeEnd) => host = host[(schemeEnd + 3)..]
        case None => ()
    }
    match (host.indexOf("/")) {
        case Some(pathStart) => host = host[..pathStart]
        case None => ()
    }
    match (host.indexOf(":")) {
        case Some(portStart) => host = host[..portStart]
        case None => ()
    }
    return host
}

func annotateTlsError(e: Exception): Exception {
    let msg = e.toString()
    let isTls = msg.contains("TLS handshake") || msg.contains("certificate verify") || msg.contains("handshake failure") ||
        msg.contains("unknown CA")
    if (!isTls) {
        return e
    }
    let hint = "TLS 握手失败：${msg}\n" + "提示：可通过 --insecure-tls 启用 TrustAll" +
        "（仅用于调试）；如使用私有 CA，可通过 --ca-bundle=/path/to/ca.pem 指定。"
    return HttpException(hint)
}
