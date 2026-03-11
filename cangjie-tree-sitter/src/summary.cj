// 高层 API：节点文本提取、统计与结构摘要
package cjtreesitter

import std.collection.*

// ============================================================
// 高层 API：节点文本提取与统计
// ============================================================

// 从源码中提取指定节点在原文中对应的文本片段
public func extractNodeText(source: String, node: NodeInfo): String {
    let sourceBytes = source.toArray()
    let startByte = Int64(node.startByte)
    let endByte = Int64(node.endByte)
    if (startByte < 0 || endByte > sourceBytes.size || startByte >= endByte) {
        return ""
    }
    return String.fromUtf8(sourceBytes[startByte..endByte])
}

// 查询指定类型的 AST 节点，同时返回每个节点在源码中的原文
public func queryNodesWithText(source: String, nodeType: String,
                               language!: CPointer<Unit> = cangjieLanguage()): Array<(NodeInfo, String)> {
    let nodes = queryNodes(source, nodeType, language: language)
    let results = ArrayList<(NodeInfo, String)>()
    for (node in nodes) {
        results.add((node, extractNodeText(source, node)))
    }
    return results.toArray()
}

// 统计源码中指定类型的 AST 节点数量（轻量级，不提取完整节点信息）
public func countNodes(source: String, nodeType: String,
                       language!: CPointer<Unit> = cangjieLanguage()): Int64 {
    let sourceBytes = source.toArray()
    var count: Int64 = 0
    unsafe {
        let parser = ts_parser_new()
        ts_parser_set_language(parser, language)
        var handle = acquireArrayRawData(sourceBytes)
        let tree = ts_parser_parse_string(parser, CPointer<Unit>(),
            CPointer<UInt8>(handle.pointer), UInt32(sourceBytes.size))
        releaseArrayRawData(handle)
        if (tree.isNotNull()) {
            let root = ts_tree_root_node(tree)
            count = countNodesByType(root, nodeType)
            ts_tree_delete(tree)
        }
        ts_parser_delete(parser)
    }
    return count
}

// ============================================================
// 高层 API：结构摘要
// ============================================================

// 生成源码的结构摘要：列出顶层函数、类、接口、结构体等定义的签名
// 返回紧凑的文本摘要，帮助 AI 快速理解文件结构，节省 Token
public func astSummary(source: String, language!: CPointer<Unit> = cangjieLanguage()): String {
    let sourceBytes = source.toArray()
    let sb = StringBuilder()
    unsafe {
        let parser = ts_parser_new()
        ts_parser_set_language(parser, language)
        var handle = acquireArrayRawData(sourceBytes)
        let tree = ts_parser_parse_string(parser, CPointer<Unit>(),
            CPointer<UInt8>(handle.pointer), UInt32(sourceBytes.size))
        releaseArrayRawData(handle)
        if (tree.isNotNull()) {
            let root = ts_tree_root_node(tree)
            collectSummaryEntries(root, sourceBytes, 0, sb)
            ts_tree_delete(tree)
        }
        ts_parser_delete(parser)
    }
    return sb.toString()
}

// 将结构摘要序列化为 JSON 字符串
public func astSummaryJson(source: String, language!: CPointer<Unit> = cangjieLanguage()): String {
    let sourceBytes = source.toArray()
    let entries = ArrayList<(String, String, UInt32, UInt32)>()
    unsafe {
        let parser = ts_parser_new()
        ts_parser_set_language(parser, language)
        var handle = acquireArrayRawData(sourceBytes)
        let tree = ts_parser_parse_string(parser, CPointer<Unit>(),
            CPointer<UInt8>(handle.pointer), UInt32(sourceBytes.size))
        releaseArrayRawData(handle)
        if (tree.isNotNull()) {
            let root = ts_tree_root_node(tree)
            collectSummaryJsonEntries(root, sourceBytes, entries)
            ts_tree_delete(tree)
        }
        ts_parser_delete(parser)
    }
    let sb = StringBuilder()
    sb.append("[")
    for (i in 0..entries.size) {
        if (i > 0) {
            sb.append(",")
        }
        let (kind, sig, startRow, endRow) = entries[i]
        sb.append("{\"kind\":\"")
        sb.append(jsonEscape(kind))
        sb.append("\",\"signature\":\"")
        sb.append(jsonEscape(sig))
        sb.append("\",\"startRow\":")
        sb.append(startRow.toString())
        sb.append(",\"endRow\":")
        sb.append(endRow.toString())
        sb.append("}")
    }
    sb.append("]")
    return sb.toString()
}

// ============================================================
// 内部辅助：统计与摘要遍历
// ============================================================

// 递归统计指定类型的节点数量
unsafe func countNodesByType(node: TSNode, targetType: String): Int64 {
    var count: Int64 = 0
    let nodeType = cStringToString(ts_node_type(node))
    if (nodeType == targetType) {
        count += 1
    }
    let childCount = ts_node_child_count(node)
    var i: UInt32 = 0
    while (i < childCount) {
        let child = ts_node_child(node, i)
        if (!ts_node_is_null(child)) {
            count += countNodesByType(child, targetType)
        }
        i += 1
    }
    return count
}

// 判断是否为结构摘要关注的顶层节点类型
func isSummaryNodeType(nodeType: String): Bool {
    return nodeType == "functionDefinition" ||
        nodeType == "mainDefinition" ||
        nodeType == "classDefinition" ||
        nodeType == "interfaceDefinition" ||
        nodeType == "structDefinition" ||
        nodeType == "enumDefinition" ||
        nodeType == "typeAliasDefinition" ||
        nodeType == "variableDeclaration" ||
        nodeType == "importDeclaration"
}

// 从源码字节中提取指定节点的首行作为签名预览
unsafe func extractFirstLine(sourceBytes: Array<Byte>, node: TSNode): String {
    let startByte = Int64(ts_node_start_byte(node))
    let endByte = Int64(ts_node_end_byte(node))
    if (startByte >= endByte || startByte >= sourceBytes.size) {
        return ""
    }
    let maxEnd = if (endByte > sourceBytes.size) { sourceBytes.size } else { endByte }
    // 取首行（遇到换行符停止）
    var lineEnd = startByte
    while (lineEnd < maxEnd) {
        if (sourceBytes[lineEnd] == b'\n' || sourceBytes[lineEnd] == b'\r') {
            break
        }
        lineEnd += 1
    }
    if (lineEnd <= startByte) {
        return ""
    }
    return String.fromUtf8(sourceBytes[startByte..lineEnd])
}

// 递归收集结构摘要条目（文本格式）
unsafe func collectSummaryEntries(node: TSNode, sourceBytes: Array<Byte>,
                                  depth: Int64, sb: StringBuilder): Unit {
    if (depth > 1) {
        return
    }
    let nodeType = cStringToString(ts_node_type(node))
    if (depth > 0 && isSummaryNodeType(nodeType)) {
        let startPt = ts_node_start_point(node)
        let endPt = ts_node_end_point(node)
        let firstLine = extractFirstLine(sourceBytes, node)
        if (!firstLine.isEmpty()) {
            sb.append("L${startPt.row.toString()}-${endPt.row.toString()} [${nodeType}] ${firstLine}\n")
        }
    }
    let count = ts_node_child_count(node)
    var i: UInt32 = 0
    while (i < count) {
        let child = ts_node_child(node, i)
        if (!ts_node_is_null(child)) {
            collectSummaryEntries(child, sourceBytes, depth + 1, sb)
        }
        i += 1
    }
}

// 递归收集结构摘要条目（JSON 格式）
unsafe func collectSummaryJsonEntries(node: TSNode, sourceBytes: Array<Byte>,
                                      entries: ArrayList<(String, String, UInt32, UInt32)>): Unit {
    let nodeType = cStringToString(ts_node_type(node))
    if (nodeType == "translationUnit") {
        let count = ts_node_child_count(node)
        var i: UInt32 = 0
        while (i < count) {
            let child = ts_node_child(node, i)
            if (!ts_node_is_null(child)) {
                let childType = cStringToString(ts_node_type(child))
                if (isSummaryNodeType(childType)) {
                    let startPt = ts_node_start_point(child)
                    let endPt = ts_node_end_point(child)
                    let sig = extractFirstLine(sourceBytes, child)
                    if (!sig.isEmpty()) {
                        entries.add((childType, sig, startPt.row, endPt.row))
                    }
                }
            }
            i += 1
        }
    }
}
