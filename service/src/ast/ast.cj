// service AST 服务层：基于 cangjie-tree-sitter 库提供 MCP AST 工具所需的接口
package cangjiecoder.ast

import cjtreesitter.*

// 重新导出 NodeInfo 和 JSON 序列化
public type AstNodeInfo = NodeInfo

// 解析仓颉源码并返回 S-expression 字符串表示
public func treeSitterParseSexp(source: String): String {
    return parseSexp(source)
}

// 解析源码并返回根节点信息
public func treeSitterParseRootInfo(source: String): AstNodeInfo {
    return parseRootInfo(source)
}

// 查询指定类型的 AST 节点，返回所有匹配的节点信息
public func treeSitterQueryNodes(source: String, nodeType: String): Array<AstNodeInfo> {
    return queryNodes(source, nodeType)
}

// 遍历 AST 树并获取所有命名节点的摘要
public func treeSitterListNamedNodes(source: String, maxDepth!: Int64 = 4): Array<AstNodeInfo> {
    return listNamedNodes(source, maxDepth: maxDepth)
}

// JSON 序列化
public func astNodeInfoToJson(node: AstNodeInfo): String {
    return nodeInfoToJson(node)
}

public func astNodeInfoArrayToJson(nodes: Array<AstNodeInfo>): String {
    return nodeInfoArrayToJson(nodes)
}
