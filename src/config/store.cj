package cangjiecoder.config

import std.fs.*
import stdx.encoding.json.*

/**
 * 配置文件的 JSON 持久化
 *
 * 文件结构示例：
 * {
 *   "currentProvider": "huawei",
 *   "currentModel": "deepseek-v4-pro",
 *   "systemPrompt": "...",
 *   "credentials": {
 *     "huawei":   { "apiKey": "...", "endpoint": "https://..." },
 *     "deepseek": { "apiKey": "...", "endpoint": "https://..." }
 *   }
 * }
 */

public func loadConfig(): AppConfig {
    let path = resolveConfigPath()
    if (!exists(path)) {
        return AppConfig()
    }
    try {
        let bytes = File.readFrom(path)
        let text = String.fromUtf8(bytes)
        if (text.trimAscii().isEmpty()) {
            return AppConfig()
        }
        return parseConfig(text)
    } catch (_: Exception) {
        return AppConfig()
    }
}

public func saveConfig(cfg: AppConfig): Unit {
    ensureConfigDir()
    let text = serializeConfig(cfg)
    let target = resolveConfigPath()
    // 原子写入：先写临时文件，再重命名，避免中断导致配置文件损坏
    let tmpPath = Path(target.toString() + ".tmp")
    File.writeTo(tmpPath, text.toArray())
    rename(tmpPath, to: target, overwrite: true)
}

func parseConfig(text: String): AppConfig {
    let cfg = AppConfig()
    let jv = JsonValue.fromStr(text)
    let obj = jv.asObject()
    if (let Some(v) <- obj.get("currentProvider")) {
        cfg.currentProvider = v.asString().getValue()
    }
    if (let Some(v) <- obj.get("currentModel")) {
        cfg.currentModel = v.asString().getValue()
    }
    if (let Some(v) <- obj.get("systemPrompt")) {
        cfg.systemPrompt = v.asString().getValue()
    }
    if (let Some(credsValue) <- obj.get("credentials")) {
        let credsObj = credsValue.asObject()
        for ((key, value) in credsObj.getFields()) {
            let credObj = value.asObject()
            var apiKey = ""
            var endpoint = ""
            if (let Some(k) <- credObj.get("apiKey")) {
                apiKey = k.asString().getValue()
            }
            if (let Some(e) <- credObj.get("endpoint")) {
                endpoint = e.asString().getValue()
            }
            cfg.setCredential(key, apiKey, endpoint)
        }
    }
    return cfg
}

func serializeConfig(cfg: AppConfig): String {
    let obj = JsonObject()
    obj.put("currentProvider", JsonString(cfg.currentProvider))
    obj.put("currentModel", JsonString(cfg.currentModel))
    obj.put("systemPrompt", JsonString(cfg.systemPrompt))

    let credsObj = JsonObject()
    for ((id, cred) in cfg.credentials) {
        let credJson = JsonObject()
        credJson.put("apiKey", JsonString(cred.apiKey))
        credJson.put("endpoint", JsonString(cred.endpoint))
        credsObj.put(id, credJson)
    }
    obj.put("credentials", credsObj)
    return obj.toJsonString()
}
