"""数据处理工具集：包含多个数据处理函数。"""


def flatten(nested_list):
    """将嵌套列表展开为一维列表。
    例：[[1, 2], [3, [4, 5]]] → [1, 2, 3, 4, 5]
    """
    result = []
    for item in nested_list:
        if isinstance(item, list):
            result.extend(item)  # BUG: 只展开了一层，未递归
        else:
            result.append(item)
    return result


def group_by(items, key_func):
    """按 key_func 分组，返回 {key: [items...]} 字典。
    例：group_by([1,2,3,4,5], lambda x: x % 2) → {1: [1,3,5], 0: [2,4]}
    """
    groups = {}
    for item in items:
        key = key_func(item)
        if key in groups:
            groups[key] = item  # BUG: 应该 append 到列表
        else:
            groups[key] = [item]
    return groups


def moving_average(data, window):
    """计算滑动平均值。
    例：moving_average([1,2,3,4,5], 3) → [2.0, 3.0, 4.0]
    """
    if window <= 0:
        return []
    result = []
    for i in range(len(data) - window + 1):
        chunk = data[i:i + window]
        avg = sum(chunk) / window
        result.append(round(avg, 2))  # BUG: round 精度问题（实际这个没bug）
    return result


def deduplicate(items):
    """去重并保持原始顺序。
    例：[3, 1, 2, 1, 3, 4] → [3, 1, 2, 4]
    """
    seen = set()
    result = []
    for item in items:
        if item in seen:  # BUG: 逻辑反了，应该是 not in
            seen.add(item)
            result.append(item)
    return result


def chunk_list(lst, size):
    """将列表按指定大小分块。
    例：chunk_list([1,2,3,4,5], 2) → [[1,2], [3,4], [5]]
    """
    if size <= 0:
        return []
    return [lst[i:i + size] for i in range(0, len(lst), size)]
