"""LRU Cache 的单元测试。"""

import sys
from lru_cache import LRUCache


def test_basic_put_get():
    cache = LRUCache(3)
    cache.put("a", 1)
    cache.put("b", 2)
    cache.put("c", 3)
    assert cache.get("a") == 1
    assert cache.get("b") == 2
    assert cache.get("c") == 3


def test_missing_key():
    cache = LRUCache(2)
    assert cache.get("x") == -1
    cache.put("a", 1)
    assert cache.get("b") == -1


def test_eviction():
    """超出容量时应淘汰最久未使用的。"""
    cache = LRUCache(2)
    cache.put("a", 1)
    cache.put("b", 2)
    cache.put("c", 3)  # 应淘汰 "a"
    assert cache.get("a") == -1
    assert cache.get("b") == 2
    assert cache.get("c") == 3
    assert cache.size() == 2


def test_access_refreshes_lru():
    """访问 key 后该 key 不应被优先淘汰。"""
    cache = LRUCache(2)
    cache.put("a", 1)
    cache.put("b", 2)
    cache.get("a")       # 刷新 "a" 的使用时间
    cache.put("c", 3)    # 应淘汰 "b"（不是 "a"）
    assert cache.get("a") == 1
    assert cache.get("b") == -1
    assert cache.get("c") == 3


def test_update_existing():
    """更新已有 key 不应增加 size。"""
    cache = LRUCache(2)
    cache.put("a", 1)
    cache.put("b", 2)
    cache.put("a", 10)  # 更新 "a"
    assert cache.get("a") == 10
    assert cache.size() == 2


def test_keys_order():
    """keys() 应按最近使用→最久未使用的顺序返回。"""
    cache = LRUCache(3)
    cache.put("a", 1)
    cache.put("b", 2)
    cache.put("c", 3)
    cache.get("a")       # 刷新 "a"
    assert cache.keys() == ["a", "c", "b"]


def test_capacity_one():
    """容量为 1 的边界场景。"""
    cache = LRUCache(1)
    cache.put("a", 1)
    assert cache.get("a") == 1
    cache.put("b", 2)
    assert cache.get("a") == -1
    assert cache.get("b") == 2
    assert cache.size() == 1


def test_eviction_sequence():
    """连续插入触发多次淘汰。"""
    cache = LRUCache(2)
    cache.put("a", 1)
    cache.put("b", 2)
    cache.put("c", 3)  # 淘汰 a
    cache.put("d", 4)  # 淘汰 b
    assert cache.get("a") == -1
    assert cache.get("b") == -1
    assert cache.get("c") == 3
    assert cache.get("d") == 4


# ────────────────────── runner ──────────────────────

def _run_tests():
    passed = 0
    failed = 0
    errors = []
    test_funcs = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in test_funcs:
        name = fn.__name__
        try:
            fn()
            passed += 1
            print(f"  PASS  {name}")
        except Exception as e:
            failed += 1
            errors.append((name, e))
            print(f"  FAIL  {name}: {e}")
    print(f"\n{passed} passed, {failed} failed")
    if errors:
        print("\nFailed tests:")
        for name, e in errors:
            print(f"  - {name}: {e}")
    return failed == 0


if __name__ == "__main__":
    ok = _run_tests()
    sys.exit(0 if ok else 1)
