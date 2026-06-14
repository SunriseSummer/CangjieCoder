package cangjiecoder.config

import std.env.*
import std.fs.*

/**
 * 配置路径解析：跨平台返回 `~/.agents/cangjiecoder/config.json`
 *
 * - Linux/macOS：使用 `$HOME` 或 `getHomeDirectory()`
 * - Windows：优先使用 `%USERPROFILE%`，回退到 `getHomeDirectory()`
 */

public let APP_DIR_NAME: String = ".agents"
public let SUB_DIR_NAME: String = "cangjiecoder"
public let CONFIG_FILE_NAME: String = "config.json"

public func resolveHomeDir(): Path {
    match (getVariable("USERPROFILE")) {
        case Some(v) where !v.isEmpty() => return Path(v)
        case _ => ()
    }
    match (getVariable("HOME")) {
        case Some(v) where !v.isEmpty() => return Path(v)
        case _ => ()
    }
    return getHomeDirectory()
}

public func resolveConfigDir(): Path {
    return resolveHomeDir().join(APP_DIR_NAME).join(SUB_DIR_NAME)
}

public func resolveConfigPath(): Path {
    return resolveConfigDir().join(CONFIG_FILE_NAME)
}

public func ensureConfigDir(): Path {
    let dir = resolveConfigDir()
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    return dir
}
