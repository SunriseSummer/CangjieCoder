"""processor.py 的单元测试。"""

import sys
from processor import flatten, group_by, moving_average, deduplicate, chunk_list


def test_flatten_simple():
    assert flatten([[1, 2], [3, 4]]) == [1, 2, 3, 4]


def test_flatten_nested():
    """嵌套超过两层也应展开。"""
    assert flatten([[1, [2, 3]], [4]]) == [1, 2, 3, 4]


def test_flatten_empty():
    assert flatten([]) == []
    assert flatten([[], []]) == []


def test_group_by_parity():
    result = group_by([1, 2, 3, 4, 5, 6], lambda x: x % 2)
    assert result == {1: [1, 3, 5], 0: [2, 4, 6]}


def test_group_by_length():
    result = group_by(["a", "bb", "c", "ddd", "ee"], len)
    assert result == {1: ["a", "c"], 2: ["bb", "ee"], 3: ["ddd"]}


def test_moving_average():
    assert moving_average([1, 2, 3, 4, 5], 3) == [2.0, 3.0, 4.0]


def test_moving_average_window_1():
    assert moving_average([10, 20, 30], 1) == [10.0, 20.0, 30.0]


def test_moving_average_empty():
    assert moving_average([], 3) == []
    assert moving_average([1, 2], 0) == []


def test_deduplicate():
    assert deduplicate([3, 1, 2, 1, 3, 4]) == [3, 1, 2, 4]


def test_deduplicate_no_dups():
    assert deduplicate([1, 2, 3]) == [1, 2, 3]


def test_deduplicate_empty():
    assert deduplicate([]) == []


def test_deduplicate_all_same():
    assert deduplicate([5, 5, 5]) == [5]


def test_chunk_list():
    assert chunk_list([1, 2, 3, 4, 5], 2) == [[1, 2], [3, 4], [5]]


def test_chunk_list_exact():
    assert chunk_list([1, 2, 3, 4], 2) == [[1, 2], [3, 4]]


def test_chunk_list_edge():
    assert chunk_list([], 3) == []
    assert chunk_list([1, 2], 0) == []


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
