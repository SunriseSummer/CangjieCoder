// tree-sitter C FFI 层：类型声明、函数绑定与底层辅助
package cjtreesitter

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
// 底层辅助
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
