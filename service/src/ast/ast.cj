// tree-sitter FFI 绑定与 AST 服务
package cangjiecoder.ast

import std.collection.*
import std.convert.*

// ---- tree-sitter C FFI 声明 ----

@C
struct TSPoint {
    var row: UInt32 = 0
    var column: UInt32 = 0
}

@C
struct TSNode {
    var context0: UInt32 = 0
    var context1: UInt32 = 0
    var context2: UInt32 = 0
    var context3: UInt32 = 0
    var id: CPointer<Unit> = CPointer<Unit>()
    var tree: CPointer<Unit> = CPointer<Unit>()
}

@C
struct TSTreeCursor {
    var tree: CPointer<Unit> = CPointer<Unit>()
    var id: CPointer<Unit> = CPointer<Unit>()
    var context0: UInt32 = 0
    var context1: UInt32 = 0
    var context2: UInt32 = 0
}

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

// ---- 辅助函数 ----

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

// ---- AST 节点信息结构 ----

public struct AstNodeInfo {
    public AstNodeInfo(
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

// ---- 核心 AST 服务 ----

// 解析仓颉源码并返回 S-expression 字符串表示
public func treeSitterParseSexp(source: String): String {
    let sourceBytes = source.toArray()
    let result = unsafe {
        let parser = ts_parser_new()
        if (parser.isNull()) {
            return "error: failed to create parser"
        }
        let language = tree_sitter_cangjie()
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
public func treeSitterParseRootInfo(source: String): AstNodeInfo {
    let sourceBytes = source.toArray()
    return unsafe {
        let parser = ts_parser_new()
        let language = tree_sitter_cangjie()
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

// 从 TSNode 中提取节点信息
unsafe func extractNodeInfo(node: TSNode): AstNodeInfo {
    let nodeType = cStringToString(ts_node_type(node))
    let startPt = ts_node_start_point(node)
    let endPt = ts_node_end_point(node)
    return AstNodeInfo(
        nodeType,
        startPt.row, startPt.column,
        endPt.row, endPt.column,
        ts_node_start_byte(node),
        ts_node_end_byte(node),
        ts_node_is_named(node),
        ts_node_child_count(node)
    )
}

// 查询指定类型的 AST 节点，返回所有匹配的节点信息
public func treeSitterQueryNodes(source: String, nodeType: String): Array<AstNodeInfo> {
    let sourceBytes = source.toArray()
    let results = ArrayList<AstNodeInfo>()
    unsafe {
        let parser = ts_parser_new()
        let language = tree_sitter_cangjie()
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

// 递归遍历 AST 树，收集指定类型的节点
unsafe func collectNodesByType(node: TSNode, targetType: String, results: ArrayList<AstNodeInfo>): Unit {
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

// 遍历 AST 树并获取所有命名节点的摘要（用于概览）
public func treeSitterListNamedNodes(source: String, maxDepth!: Int64 = 4): Array<AstNodeInfo> {
    let sourceBytes = source.toArray()
    let results = ArrayList<AstNodeInfo>()
    unsafe {
        let parser = ts_parser_new()
        let language = tree_sitter_cangjie()
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

// 递归收集命名节点（限制深度避免输出过大）
unsafe func collectNamedNodes(node: TSNode, depth: Int64, maxDepth: Int64,
                               results: ArrayList<AstNodeInfo>): Unit {
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

// ---- JSON 序列化辅助 ----

public func astNodeInfoToJson(node: AstNodeInfo): String {
    let sb = StringBuilder()
    sb.append("{\"type\":\"")
    sb.append(jsonEscapeString(node.nodeType))
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

public func astNodeInfoArrayToJson(nodes: Array<AstNodeInfo>): String {
    let sb = StringBuilder()
    sb.append("[")
    for (i in 0..nodes.size) {
        if (i > 0) {
            sb.append(",")
        }
        sb.append(astNodeInfoToJson(nodes[i]))
    }
    sb.append("]")
    return sb.toString()
}

// 简单 JSON 字符串转义
func jsonEscapeString(s: String): String {
    return s.replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
}
