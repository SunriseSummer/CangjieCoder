"""LRU Cache 实现：基于双向链表 + 字典。"""


class _Node:
    """双向链表节点。"""
    __slots__ = ("key", "value", "prev", "next")

    def __init__(self, key, value):
        self.key = key
        self.value = value
        self.prev = None
        self.next = None


class LRUCache:
    """固定容量的 LRU（最近最少使用）缓存。

    支持 O(1) 的 get 和 put 操作。
    """

    def __init__(self, capacity):
        if capacity <= 0:
            raise ValueError("capacity must be positive")
        self.capacity = capacity
        self._map = {}
        # 哨兵节点简化链表操作
        self._head = _Node(None, None)
        self._tail = _Node(None, None)
        self._head.next = self._tail
        self._tail.prev = self._head

    def get(self, key):
        """获取 key 对应的值，不存在返回 -1。访问后该 key 变为最近使用。"""
        if key not in self._map:
            return -1
        node = self._map[key]
        # BUG: 忘记将访问节点移到链表头部（应该移动以标记为最近使用）
        return node.value

    def put(self, key, value):
        """插入或更新 key-value 对。超出容量时淘汰最近最少使用的条目。"""
        if key in self._map:
            node = self._map[key]
            node.value = value
            self._move_to_head(node)
            return
        node = _Node(key, value)
        self._map[key] = node
        self._add_to_head(node)
        if len(self._map) > self.capacity:
            removed = self._remove_tail()
            # BUG: 从 map 中删除时用了错误的 key
            del self._map[key]

    def size(self):
        """返回当前缓存中的条目数。"""
        return len(self._map)

    def keys(self):
        """按最近使用到最久未使用的顺序返回所有 key。"""
        result = []
        curr = self._head.next
        while curr != self._tail:
            result.append(curr.key)
            curr = curr.next
        return result

    def _add_to_head(self, node):
        """将节点添加到链表头部（最近使用端）。"""
        node.prev = self._head
        node.next = self._head.next
        self._head.next.prev = node
        self._head.next = node

    def _remove_node(self, node):
        """从链表中移除节点。"""
        node.prev.next = node.next
        node.next.prev = node.prev

    def _move_to_head(self, node):
        """将节点移到链表头部。"""
        self._remove_node(node)
        self._add_to_head(node)

    def _remove_tail(self):
        """移除链表尾部节点（最久未使用），返回该节点。"""
        node = self._tail.prev
        self._remove_node(node)
        return node
