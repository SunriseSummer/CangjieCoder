// cangjie-tree-sitter：tree-sitter 引擎的仓颉封装
// 默认集成 tree-sitter-cangjie 插件，也支持接入其他语言插件。
package cjtreesitter

import std.collection.*

// ============================================================
// tree-sitter C FFI 类型声明
// ============================================================

@C
public struct TSPoint {
    public var row: UInt32 = 0
    public var column: UInt32 = 0
}

@C
public struct TSNode {
    public var context0: UInt32 = 0
    public var context1: UInt32 = 0
    public var context2: UInt32 = 0
    public var context3: UInt32 = 0
    public var id: CPointer<Unit> = CPointer<Unit>()
    public var tree: CPointer<Unit> = CPointer<Unit>()
}

@C
public struct TSTreeCursor {
    public var tree: CPointer<Unit> = CPointer<Unit>()
    public var id: CPointer<Unit> = CPointer<Unit>()
    public var context0: UInt32 = 0
    public var context1: UInt32 = 0
    public var context2: UInt32 = 0
}

// ============================================================
// tree-sitter C FFI 函数声明
// ============================================================

foreign {
    func tree_sitter_cangjie(): CPointer<Unit>
    func ts_parser_new(): CPointer<Unit>
    func ts_parser_delete(parser: CPointer<Unit>): Unit
    func ts_parser_set_language(parser: CPointer<Unit>, language: CPointer<Unit>): Bool
    func ts_parser_parse_string(parser: CPointer<Unit>, oldTree: CPointer<Unit>,
                                source: CPointer<UInt8>, length: UInt32): CPointer<Unit>
    func ts_tree_delete(tree: CPointer<Unit>): Unit
    func ts_tree_root_node(tree: CPointer<Unit>): TSNode
    func ts_node_type(node: TSNode): CPointer<UInt8>
    func ts_node_string(node: TSNode): CPointer<UInt8>
    func ts_node_start_point(node: TSNode): TSPoint
    func ts_node_end_point(node: TSNode): TSPoint
    func ts_node_start_byte(node: TSNode): UInt32
    func ts_node_end_byte(node: TSNode): UInt32
    func ts_node_child_count(node: TSNode): UInt32
    func ts_node_named_child_count(node: TSNode): UInt32
    func ts_node_child(node: TSNode, index: UInt32): TSNode
    func ts_node_named_child(node: TSNode, index: UInt32): TSNode
    func ts_node_is_null(node: TSNode): Bool
    func ts_node_is_named(node: TSNode): Bool
    func ts_tree_cursor_new(node: TSNode): TSTreeCursor
    func ts_tree_cursor_delete(cursor: CPointer<TSTreeCursor>): Unit
    func ts_tree_cursor_current_node(cursor: CPointer<TSTreeCursor>): TSNode
    func ts_tree_cursor_goto_first_child(cursor: CPointer<TSTreeCursor>): Bool
    func ts_tree_cursor_goto_next_sibling(cursor: CPointer<TSTreeCursor>): Bool
    func ts_tree_cursor_goto_parent(cursor: CPointer<TSTreeCursor>): Bool
}

foreign func free(ptr: CPointer<Unit>): Unit

// ============================================================
// 内部辅助
// ============================================================

// 将 C 字符串指针转换为仓颉 String
unsafe func cStringToString(ptr: CPointer<UInt8>): String {
    if (ptr.isNull()) {
        return ""
    }
    var len: Int64 = 0
    while (ptr.read(len) != 0) {
        len += 1
    }
    let bytes = Array<Byte>(len, {i => ptr.read(i)})
    return String.fromUtf8(bytes)
}

// ============================================================
// 语言插件接口
// ============================================================

// 获取内置的 tree-sitter-cangjie 语言指针
public func cangjieLanguage(): CPointer<Unit> {
    return unsafe { tree_sitter_cangjie() }
}

// ============================================================
// 节点信息结构
// ============================================================

// AST 节点的元信息
public struct NodeInfo {
    public NodeInfo(
        public let nodeType: String,
        public let startRow: UInt32,
        public let startColumn: UInt32,
        public let endRow: UInt32,
        public let endColumn: UInt32,
        public let startByte: UInt32,
        public let endByte: UInt32,
        public let isNamed: Bool,
        public let childCount: UInt32
    ) {}
}

// 从原始 TSNode 提取 NodeInfo
unsafe func extractNodeInfo(node: TSNode): NodeInfo {
    let nodeType = cStringToString(ts_node_type(node))
    let startPt = ts_node_start_point(node)
    let endPt = ts_node_end_point(node)
    return NodeInfo(
        nodeType,
        startPt.row, startPt.column,
        endPt.row, endPt.column,
        ts_node_start_byte(node),
        ts_node_end_byte(node),
        ts_node_is_named(node),
        ts_node_child_count(node)
    )
}

// ============================================================
// 高层 API：解析
// ============================================================

// 解析源码并返回 S-expression 字符串表示
// language 参数指定语言插件，默认使用内置的仓颉语言
public func parseSexp(source: String, language!: CPointer<Unit> = cangjieLanguage()): String {
    let sourceBytes = source.toArray()
    let result = unsafe {
        let parser = ts_parser_new()
        if (parser.isNull()) {
            return "error: failed to create parser"
        }
        if (!ts_parser_set_language(parser, language)) {
            ts_parser_delete(parser)
            return "error: failed to set language"
        }
        var handle = acquireArrayRawData(sourceBytes)
        let tree = ts_parser_parse_string(parser, CPointer<Unit>(),
            CPointer<UInt8>(handle.pointer), UInt32(sourceBytes.size))
        releaseArrayRawData(handle)
        if (tree.isNull()) {
            ts_parser_delete(parser)
            return "error: failed to parse source"
        }
        let root = ts_tree_root_node(tree)
        let sexpPtr = ts_node_string(root)
        let sexp = cStringToString(sexpPtr)
        free(CPointer<Unit>(sexpPtr))
        ts_tree_delete(tree)
        ts_parser_delete(parser)
        sexp
    }
    return result
}

// 解析源码并返回根节点信息
public func parseRootInfo(source: String, language!: CPointer<Unit> = cangjieLanguage()): NodeInfo {
    let sourceBytes = source.toArray()
    return unsafe {
        let parser = ts_parser_new()
        ts_parser_set_language(parser, language)
        var handle = acquireArrayRawData(sourceBytes)
        let tree = ts_parser_parse_string(parser, CPointer<Unit>(),
            CPointer<UInt8>(handle.pointer), UInt32(sourceBytes.size))
        releaseArrayRawData(handle)
        let root = ts_tree_root_node(tree)
        let info = extractNodeInfo(root)
        ts_tree_delete(tree)
        ts_parser_delete(parser)
        info
    }
}

// ============================================================
// 高层 API：节点查询
// ============================================================

// 查询指定类型的 AST 节点，返回所有匹配的节点信息
public func queryNodes(source: String, nodeType: String,
                       language!: CPointer<Unit> = cangjieLanguage()): Array<NodeInfo> {
    let sourceBytes = source.toArray()
    let results = ArrayList<NodeInfo>()
    unsafe {
        let parser = ts_parser_new()
        ts_parser_set_language(parser, language)
        var handle = acquireArrayRawData(sourceBytes)
        let tree = ts_parser_parse_string(parser, CPointer<Unit>(),
            CPointer<UInt8>(handle.pointer), UInt32(sourceBytes.size))
        releaseArrayRawData(handle)
        if (tree.isNotNull()) {
            let root = ts_tree_root_node(tree)
            collectNodesByType(root, nodeType, results)
            ts_tree_delete(tree)
        }
        ts_parser_delete(parser)
    }
    return results.toArray()
}

// 遍历 AST 树并获取所有命名节点的摘要（限制深度避免输出过大）
public func listNamedNodes(source: String, maxDepth!: Int64 = 4,
                           language!: CPointer<Unit> = cangjieLanguage()): Array<NodeInfo> {
    let sourceBytes = source.toArray()
    let results = ArrayList<NodeInfo>()
    unsafe {
        let parser = ts_parser_new()
        ts_parser_set_language(parser, language)
        var handle = acquireArrayRawData(sourceBytes)
        let tree = ts_parser_parse_string(parser, CPointer<Unit>(),
            CPointer<UInt8>(handle.pointer), UInt32(sourceBytes.size))
        releaseArrayRawData(handle)
        if (tree.isNotNull()) {
            let root = ts_tree_root_node(tree)
            collectNamedNodes(root, 0, maxDepth, results)
            ts_tree_delete(tree)
        }
        ts_parser_delete(parser)
    }
    return results.toArray()
}

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
// 内部遍历辅助
// ============================================================

// 递归遍历 AST 树，收集指定类型的节点
unsafe func collectNodesByType(node: TSNode, targetType: String,
                               results: ArrayList<NodeInfo>): Unit {
    let nodeType = cStringToString(ts_node_type(node))
    if (nodeType == targetType) {
        results.add(extractNodeInfo(node))
    }
    let count = ts_node_child_count(node)
    var i: UInt32 = 0
    while (i < count) {
        let child = ts_node_child(node, i)
        if (!ts_node_is_null(child)) {
            collectNodesByType(child, targetType, results)
        }
        i += 1
    }
}

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

// 递归收集命名节点
unsafe func collectNamedNodes(node: TSNode, depth: Int64, maxDepth: Int64,
                              results: ArrayList<NodeInfo>): Unit {
    if (depth > maxDepth) {
        return
    }
    if (ts_node_is_named(node)) {
        results.add(extractNodeInfo(node))
    }
    let count = ts_node_child_count(node)
    var i: UInt32 = 0
    while (i < count) {
        let child = ts_node_child(node, i)
        if (!ts_node_is_null(child)) {
            collectNamedNodes(child, depth + 1, maxDepth, results)
        }
        i += 1
    }
}

// ============================================================
// JSON 序列化辅助
// ============================================================

// 将 NodeInfo 序列化为 JSON 字符串
public func nodeInfoToJson(node: NodeInfo): String {
    let sb = StringBuilder()
    sb.append("{\"type\":\"")
    sb.append(jsonEscape(node.nodeType))
    sb.append("\",\"startRow\":")
    sb.append(node.startRow.toString())
    sb.append(",\"startColumn\":")
    sb.append(node.startColumn.toString())
    sb.append(",\"endRow\":")
    sb.append(node.endRow.toString())
    sb.append(",\"endColumn\":")
    sb.append(node.endColumn.toString())
    sb.append(",\"startByte\":")
    sb.append(node.startByte.toString())
    sb.append(",\"endByte\":")
    sb.append(node.endByte.toString())
    sb.append(",\"isNamed\":")
    sb.append(node.isNamed.toString())
    sb.append(",\"childCount\":")
    sb.append(node.childCount.toString())
    sb.append("}")
    return sb.toString()
}

// 将 NodeInfo 数组序列化为 JSON 数组字符串
public func nodeInfoArrayToJson(nodes: Array<NodeInfo>): String {
    let sb = StringBuilder()
    sb.append("[")
    for (i in 0..nodes.size) {
        if (i > 0) {
            sb.append(",")
        }
        sb.append(nodeInfoToJson(nodes[i]))
    }
    sb.append("]")
    return sb.toString()
}

// JSON 字符串转义
func jsonEscape(s: String): String {
    return s.replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
}
