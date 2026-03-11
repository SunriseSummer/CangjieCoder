// cangjie-tree-sitter：核心类型、解析与节点查询 API
// FFI 绑定见 ffi.cj，结构摘要见 summary.cj，JSON 序列化见 json.cj
package cjtreesitter

import std.collection.*

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
// 内部辅助：节点遍历
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

