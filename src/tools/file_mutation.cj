package cangjiecoder.tools

import std.fs.*

/**
 * 文件修改类工具共用的前置动作
 *
 * 写入前先记录 journal，再由调用方执行实际文件修改
 */
func recordFileMutation(journal: ?FileJournal, path: String, toolName: String): Unit {
    match (journal) {
        case Some(j) => j.record(path, toolName)
        case None => ()
    }
}

func ensureParentDirectory(filePath: Path): Unit {
    let parent = filePath.parent
    if (!parent.toString().isEmpty() && !exists(parent)) {
        Directory.create(parent, recursive: true)
    }
}
