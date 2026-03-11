// JSON 序列化辅助：NodeInfo 的 JSON 输出与转义
package cjtreesitter

// ============================================================
// JSON 序列化
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
